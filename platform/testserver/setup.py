from setuptools import setup

setup(
    name='routing_project_server',
    packages=['routing_project_server'],
    include_package_data=True,
    install_requires=[
        'flask', 'bjoern',  # TODO
    ],
)
