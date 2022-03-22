from setuptools import setup

setup(
    name='routing_project_server',
    version="1.0",
    packages=['routing_project_server'],
    include_package_data=True,
    zip_safe=False,
    install_requires=[
        'flask', 'bjoern', 'flask-basicauth',
    ],
)
