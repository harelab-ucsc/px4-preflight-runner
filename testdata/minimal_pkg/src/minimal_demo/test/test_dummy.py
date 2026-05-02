"""Trivial unit test that proves the colcon test plumbing is wired up."""


def test_python_arithmetic_still_works():
    assert 2 + 2 == 4


def test_minimal_demo_importable():
    import minimal_demo  # noqa: F401
