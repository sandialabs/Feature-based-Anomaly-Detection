#!/usr/bin/env python
# -*- encoding: utf-8 -*-

import io
import re
from glob import glob
from os.path import basename
from os.path import dirname
from os.path import join
from os.path import splitext

from setuptools import find_packages
from setuptools import setup


def read(*names, **kwargs):
    with io.open(
        join(dirname(__file__), *names),
        encoding=kwargs.get('encoding', 'utf8')
    ) as fh:
        return fh.read()


def get_version_for_conda_meta_yaml():
    """
    load_setup_py_data() will actually run arbitrary code from setup.py,
    so in theory we ought to be able to get the version without needing to set it manually.
    https://stackoverflow.com/questions/38919840/get-package-version-for-conda-meta-yaml-from-source-file
    """
    return '0.0.0'
    # return pkg_resources.get_distribution(__name__).version


setup(
    name='feature-anomaly-detection-system',
    use_scm_version={
        'local_scheme': 'dirty-tag',
        'write_to': 'src/feature_anomaly_detection/_version.py',
        'fallback_version': '0.0.0',
    },
    get_version_for_conda_meta_yaml=get_version_for_conda_meta_yaml,
    description='An example package. Generated with cookiecutter-pylibrary.',
    long_description='%s\n%s' % (
        re.compile('^.. start-badges.*^.. end-badges', re.M | re.S).sub('', read('README.rst')),
        re.sub(':[a-z]+:`~?(.*?)`', r'``\1``', read('CHANGELOG.rst'))
    ),
    author='David Alexander Hannasch',
    author_email='dahanna@sandia.gov',
    url='https://cee-gitlab.sandia.gov/video-anomaly-detection/feature-anomaly-detection',
    packages=find_packages('src'),
    package_dir={'': 'src'},
    py_modules=[splitext(basename(path))[0] for path in glob('src/*.py')],
    include_package_data=True,
    zip_safe=False,
    classifiers=[
        # complete classifier list: http://pypi.python.org/pypi?%3Aaction=list_classifiers
        'Development Status :: 5 - Production/Stable',
        'Intended Audience :: Developers',
        'Operating System :: Unix',
        'Operating System :: POSIX',
        'Operating System :: Microsoft :: Windows',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3 :: Only',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: Implementation :: CPython',
        'Programming Language :: Python :: Implementation :: PyPy',
        # uncomment if you test on these interpreters:
        # 'Programming Language :: Python :: Implementation :: IronPython',
        # 'Programming Language :: Python :: Implementation :: Jython',
        # 'Programming Language :: Python :: Implementation :: Stackless',
        'Topic :: Utilities',
    ],
    project_urls={
        'Documentation': 'http://video-anomaly-detection.cee-gitlab.lan/feature-anomaly-detection',
        'Changelog': 'http://video-anomaly-detection.cee-gitlab.lan/feature-anomaly-detectionen/latest/changelog.html',
        'Issue Tracker': 'https://cee-gitlab.sandia.gov/video-anomaly-detection/feature-anomaly-detection/issues',
    },
    keywords=[
        # eg: 'keyword1', 'keyword2', 'keyword3',
    ],
    python_requires='>=3.6',
    install_requires=[
        'click',
        'torch',
        'torchvision',
        # eg: 'aspectlib==1.1.1', 'six>=1.7',
    ],
    extras_require={
        # eg:
        #   'rst': ['docutils>=0.11'],
        #   ':python_version=="2.6"': ['argparse'],
    },
    setup_requires=[
        'setuptools_scm>=3.3.1',
    ],
    entry_points={
        'console_scripts': [
            'feature-anomaly-detection-system = feature_anomaly_detection.cli:main',
        ]
    },
)
