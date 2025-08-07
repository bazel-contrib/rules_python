import lib1

def test_add_numbers():
    result = lib1.add_numbers(2, 3)
    assert result == 5, f"Expected 5, got {result}"

if __name__ == "__main__":
    test_add_numbers()
    print("lib1 tests passed")