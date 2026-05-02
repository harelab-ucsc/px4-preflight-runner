from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription(
        [
            Node(
                package="minimal_demo",
                executable="status_listener.py",
                name="status_listener",
                output="screen",
            ),
        ]
    )
