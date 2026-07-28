"A trivial zipapp that prints a message"


def main():
    print("Hello from zipapp")
    try:
        import some_dep

        print(f"dep: {some_dep}")

        import pkgdep.pkgmod

        print(f"dep: {pkgdep.pkgmod}")
    except ImportError as e:
        import sys

        e.add_note(
            "Failed to import a dependency.\n" + "sys.path:\n" + "\n".join(sys.path)
        )
        raise


if __name__ == "__main__":
    main()
