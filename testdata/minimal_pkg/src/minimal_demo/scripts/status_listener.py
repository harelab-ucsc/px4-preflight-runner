#!/usr/bin/env python3
"""Subscribe to /fmu/out/vehicle_status and exit cleanly on shutdown.

Used by the runner self-test fixture to prove the uXRCE-DDS bridge is up
and topics from PX4 are flowing into ROS 2.
"""

import rclpy
from rclpy.node import Node
from rclpy.qos import (
    DurabilityPolicy,
    HistoryPolicy,
    QoSProfile,
    ReliabilityPolicy,
)
from px4_msgs.msg import VehicleStatus


class StatusListener(Node):
    def __init__(self):
        super().__init__("minimal_status_listener")
        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )
        self.received = 0
        self.create_subscription(
            VehicleStatus, "/fmu/out/vehicle_status", self._on_status, qos
        )

    def _on_status(self, msg):
        self.received += 1
        if self.received == 1:
            self.get_logger().info(
                f"first vehicle_status received: nav_state={msg.nav_state}"
            )


def main():
    rclpy.init()
    node = StatusListener()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.get_logger().info(f"received {node.received} status messages")
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == "__main__":
    main()
