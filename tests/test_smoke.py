import python_cpp


def test_hello() -> None:
    assert isinstance(python_cpp.hello(), str)
