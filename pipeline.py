# encoding=utf8
import datetime
import functools
import hashlib
import os
import random
import re
import shutil
import socket
import string
import subprocess
import sys
import time
from distutils.version import StrictVersion

import requests
import seesaw
from seesaw.externalprocess import WgetDownload
from seesaw.pipeline import Pipeline
from seesaw.project import Project
from seesaw.util import find_executable
from seesaw.config import realize, NumberConfigValue
from seesaw.externalprocess import ExternalProcess, RsyncUpload
from seesaw.item import ItemInterpolation, ItemValue
from seesaw.task import SimpleTask, LimitConcurrent, Task
from seesaw.tracker import GetItemFromTracker, PrepareStatsForTracker, \
    UploadWithTracker, SendDoneToTracker
from tornado.ioloop import IOLoop
import zstandard

if StrictVersion(seesaw.__version__) < StrictVersion('0.8.5'):
    raise Exception('This pipeline needs seesaw version 0.8.5 or higher.')

###########################################################################
# Find a useful Wget+Lua executable.
#
# WGET_AT will be set to the first path that
# 1. does not crash with --version, and
# 2. prints the required version string

WGET_AT = find_executable(
    'Wget+AT',
    ['GNU Wget 1.20.3-at.20200902.01'],
    ['./wget-at']
)

if not WGET_AT:
    raise Exception('No usable Wget+At found.')

###########################################################################
# The version number of this pipeline definition.
#
# Update this each time you make a non-cosmetic change.
# It will be added to the WARC files and reported to the tracker.
VERSION = '20200911.01'
USER_AGENT = 'Archive Team'
TRACKER_ID = 'github'
TRACKER_HOST = 'trackerproxy.archiveteam.org'


class CheckIP(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, 'CheckIP')
        self._counter = 0

    def process(self, item):
        # NEW for 2014! Check if we are behind firewall/proxy

        if self._counter <= 0:
            item.log_output('Checking IP address.')
            ip_set = set()

            ip_set.add(socket.gethostbyname('twitter.com'))
            ip_set.add(socket.gethostbyname('facebook.com'))
            ip_set.add(socket.gethostbyname('youtube.com'))
            ip_set.add(socket.gethostbyname('microsoft.com'))
            ip_set.add(socket.gethostbyname('icanhas.cheezburger.com'))
            ip_set.add(socket.gethostbyname('archiveteam.org'))

            if len(ip_set) != 6:
                item.log_output('Got IP addresses: {0}'.format(ip_set))
                item.log_output(
                    'Are you behind a firewall/proxy? That is a big no-no!')
                raise Exception(
                    'Are you behind a firewall/proxy? That is a big no-no!')

        # Check only occasionally
        if self._counter <= 0:
            self._counter = 10
        else:
            self._counter -= 1


class PrepareDirectories(SimpleTask):
    def __init__(self, warc_prefix):
        SimpleTask.__init__(self, 'PrepareDirectories')
        self.warc_prefix = warc_prefix

    def process(self, item):
        item_name = item['item_name']
        escaped_item_name = item_name.replace(':', '_').replace('/', '_').replace('~', '_')
        dirname = '/'.join((item['data_dir'], escaped_item_name))

        if os.path.isdir(dirname):
            shutil.rmtree(dirname)

        os.makedirs(dirname)

        item['item_dir'] = dirname
        item['warc_file_base'] = '-'.join([
            self.warc_prefix,
            escaped_item_name[:45],
            hashlib.sha1(item_name.encode('utf8')).hexdigest()[:10],
            time.strftime('%Y%m%d-%H%M%S')
        ])

        open('%(item_dir)s/%(warc_file_base)s.warc.gz' % item, 'w').close()
        with open('%(item_dir)s/%(warc_file_base)s_data.txt' % item, 'w') as f:
            data = item['item_name'].split(':')
            r = requests.get('http://trackerproxy.archiveteam.org/now')
            assert r.status_code == 200
            f.write(':'.join(['web', r.text.split('.')[0]] + data[2:]))


class MoveFiles(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, 'MoveFiles')

    def process(self, item):
        os.rename('%(item_dir)s/%(warc_file_base)s.warc.zst' % item,
            '%(data_dir)s/%(warc_file_base)s.%(dict_project)s.%(dict_id)s.warc.zst' % item)
        os.rename('%(item_dir)s/%(warc_file_base)s_data.txt' % item,
            '%(data_dir)s/%(warc_file_base)s_data.txt' % item)

        shutil.rmtree('%(item_dir)s' % item)


class ChooseTargetAndUpload(Task):
    def __init__(self):
        Task.__init__(self, 'ChooseTargetAndUpload')
        self.retry_sleep = 10

    def enqueue(self, item):
        self.start_item(item)
        item.log_output('Starting %s for %s\n' % (self, item.description()))
        self.process(item)

    def process(self, item):
        try:
            target = self.find_target(item)
            assert target is not None
        except:
            item.log_output('Could not get rsync target.')
            return self.retry(item)
        inner_task = RsyncUpload(
            target,
            [
                '%(data_dir)s/%(warc_file_base)s.%(dict_project)s.%(dict_id)s.warc.zst' % item,
                '%(data_dir)s/%(warc_file_base)s_data.txt' % item
            ],
            target_source_path='%(data_dir)s/' % item,
            extra_args=[
                '--recursive',
                '--partial',
                '--partial-dir', '.rsync-tmp',
                '--min-size', '1',
                '--no-compress',
                '--compress-level', '0'
            ],
            max_tries=1
        )
        inner_task.on_complete_item = lambda task, item: self.complete_item(item)
        inner_task.on_fail_item = lambda task, item: self.retry(item)
        inner_task.enqueue(item)

    def retry(self, item):
        item.log_output('Failed to upload, retrying...')
        IOLoop.instance().add_timeout(
            datetime.timedelta(seconds=self.retry_sleep),
            functools.partial(self.process, item)
        )

    def find_target(self, item):
        item.log_output('Requesting targets.')
        r = requests.get('https://{}/{}/upload_targets'
                         .format(TRACKER_HOST, TRACKER_ID))
        targets = r.json()
        random.shuffle(targets)
        for target in targets:
            item.log_output('Trying target {}.'.format(target))
            domain = re.search('^[^:]+://([^/:]+)', target).group(1)
            size = os.path.getsize(
                '%(data_dir)s/%(warc_file_base)s.%(dict_project)s.%(dict_id)s.warc.zst' % item
            )
            r = requests.get(
                'http://{}:3000/'.format(domain),
                params={
                    'name': item['item_name'],
                    'size': size
                },
                timeout=3
            )
            if r.json()['accepts']:
                return target.replace(':downloader', item['stats']['downloader'])


def get_hash(filename):
    with open(filename, 'rb') as in_file:
        return hashlib.sha1(in_file.read()).hexdigest()

CWD = os.getcwd()
PIPELINE_SHA1 = get_hash(os.path.join(CWD, 'pipeline.py'))
LUA_SHA1 = get_hash(os.path.join(CWD, 'github.lua'))


def stats_id_function(item):
    d = {
        'pipeline_hash': PIPELINE_SHA1,
        'lua_hash': LUA_SHA1,
        'python_version': sys.version,
    }

    return d


class ZstdDict(object):
    created = 0
    data = None

    @classmethod
    def get_dict(cls):
        if cls.data is not None and time.time() - cls.created < 1800:
            return cls.data
        response = requests.get(
            'http://trackerproxy.archiveteam.org:25654/dictionary',
            params={
                'project': 'github'
            }
        )
        response.raise_for_status()
        response = response.json()
        if cls.data is not None and response['id'] == cls.data['id']:
            cls.created = time.time()
            return cls.data
        print('Downloading latest dictionary.')
        response_dict = requests.get(response['url'])
        response_dict.raise_for_status()
        raw_data = response_dict.content
        if hashlib.sha256(raw_data).hexdigest() != response['sha256']:
            raise ValueError('Hash of downloaded dictionary does not match.')
        if raw_data[:4] == b'\x28\xB5\x2F\xFD':
            raw_data = zstandard.ZstdDecompressor().decompress(raw_data)
        cls.data = {
            'id': response['id'],
            'dict': raw_data
        }
        cls.created = time.time()
        return cls.data


class WgetArgs(object):
    def realize(self, item):
        wget_args = [
            WGET_AT,
            '-U', USER_AGENT,
            '-nv',
            '--no-cookies',
            '--content-on-error',
            '--lua-script', 'github.lua',
            '-o', ItemInterpolation('%(item_dir)s/wget.log'),
            '--no-check-certificate',
            '--output-document', ItemInterpolation('%(item_dir)s/wget.tmp'),
            '--truncate-output',
            '-e', 'robots=off',
            '--rotate-dns',
            '--recursive', '--level=inf',
            '--no-parent',
            '--page-requisites',
            '--timeout', '30',
            '--tries', 'inf',
            '--domains', 'github.com',
            '--span-hosts',
            '--waitretry', '30',
            '--warc-file', ItemInterpolation('%(item_dir)s/%(warc_file_base)s'),
            '--warc-header', 'operator: Archive Team',
            '--warc-header', 'github-dld-script-version: ' + VERSION,
            '--warc-header', ItemInterpolation('github-item: %(item_name)s'),
            '--warc-dedup-url-agnostic',
            '--warc-compression-use-zstd',
            '--warc-zstd-dict-no-include'
        ]

        dict_data = ZstdDict.get_dict()
        with open(os.path.join(item['item_dir'], 'zstdict'), 'wb') as f:
            f.write(dict_data['dict'])
        item['dict_id'] = dict_data['id']
        item['dict_project'] = 'github'
        wget_args.extend([
            '--warc-zstd-dict', ItemInterpolation('%(item_dir)s/zstdict'),
        ])

        item_name = item['item_name']
        item_type, item_config, item_value = item_name.split(':', 2)

        item['item_type'] = item_type
        item['item_value'] = item_value
        item['item_config'] = item_config

        assert item_config == 'initial'

        if item_type == 'web':
            wget_args.extend(['--warc-header', 'github-repo-web: ' + str(item_value)])
            wget_args.append('https://github.com/{}'.format(item_value))

        if 'bind_address' in globals():
            wget_args.extend(['--bind-address', globals()['bind_address']])
            print('')
            print('*** Wget will bind address at {0} ***'.format(
                globals()['bind_address']))
            print('')

        return realize(wget_args, item)

###########################################################################
# Initialize the project.
#
# This will be shown in the warrior management panel. The logo should not
# be too big. The deadline is optional.
project = Project(
    title = 'GitHub',
    project_html = '''
    <img class="project-logo" alt="logo" src="https://www.archiveteam.org/images/2/21/Github-icon.png" height="50px"/>
    <h2>github.com <span class="links"><a href="https://github.com/">Website</a> &middot; <a href="http://tracker.archiveteam.org/github/">Leaderboard</a></span></h2>
    '''
)

pipeline = Pipeline(
    CheckIP(),
    GetItemFromTracker('http://%s/%s' % (TRACKER_HOST, TRACKER_ID), downloader,
        VERSION),
    PrepareDirectories(warc_prefix='github'),
    WgetDownload(
        WgetArgs(),
        max_tries=2,
        accept_on_exit_code=[0, 4, 8],
        env={
            'item_dir': ItemValue('item_dir'),
            'item_value': ItemValue('item_value'),
            'item_type': ItemValue('item_type'),
            'item_config': ItemValue('item_config'),
            'warc_file_base': ItemValue('warc_file_base'),
        }
    ),
    PrepareStatsForTracker(
        defaults={'downloader': downloader, 'version': VERSION},
        file_groups={
            'data': [
                ItemInterpolation('%(item_dir)s/%(warc_file_base)s.warc.zst')
            ]
        },
        id_function=stats_id_function,
    ),
    MoveFiles(),
    LimitConcurrent(NumberConfigValue(min=1, max=20, default='2',
        name='shared:rsync_threads', title='Rsync threads',
        description='The maximum number of concurrent uploads.'),
        ChooseTargetAndUpload(),
    ),
    SendDoneToTracker(
        tracker_url='http://%s/%s' % (TRACKER_HOST, TRACKER_ID),
        stats=ItemValue('stats')
    )
)

