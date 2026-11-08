load("@bazel_skylib//rules:write_file.bzl", "write_file")

write_file(
    name = "generated_file",
    out = "generated_file.txt",
    content = ["Hello world from requests"],
)

filegroup(
    name = "whl_archive",
    # The archive may live in a separate repository. Use the wheel target
    # instead of assuming that the archive is beside the extracted files.
    srcs = [":whl_file"],
)
