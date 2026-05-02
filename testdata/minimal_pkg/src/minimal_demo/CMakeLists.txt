cmake_minimum_required(VERSION 3.8)
project(minimal_demo)

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)
find_package(rclpy REQUIRED)
find_package(px4_msgs REQUIRED)

ament_python_install_package(${PROJECT_NAME})

install(PROGRAMS
  scripts/status_listener.py
  DESTINATION lib/${PROJECT_NAME}
)

install(DIRECTORY launch
  DESTINATION share/${PROJECT_NAME}
)

if(BUILD_TESTING)
  find_package(ament_cmake_pytest REQUIRED)
  ament_add_pytest_test(test_dummy test/test_dummy.py)
endif()

ament_package()
