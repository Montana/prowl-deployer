from distutils.core import setup
from setuptools import find_packages

setup(
    name='deployer',
    version='0.0.4',
    packages=find_packages(),
    package_data={'deployer': ['template/*.conf']},
    url='https://www.getprowl.com',
    license='MIT',
    install_requires=['colorama', 'argparse', 'virtualenv'],
    author='Montana Mendy',
    author_email='montana@getprowl.com',
    description='A handful tool to install and manage multiple django apps',
    entry_points={
        'console_scripts': [
            'deployer = deployer.cli:main',
        ]
    }
)
