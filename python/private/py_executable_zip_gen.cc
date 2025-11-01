// Copyright 2025 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Wrapper for zipper that processes Python zip manifest generation.
//
// This C++ script wraps `@bazel_tools//tools/zip/zipper` to produce the
// input manifest for the zipper tool during build time, rather than at
// analysis time.
//
// Usage: py_executable_zip_gen [flags...] <input_files_manifest>
//   Flags are passed as regular command-line arguments
//   Input files manifest contains the list of files to include (short_path=disk_path)

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include "tools/cpp/runfiles/runfiles.h"

using bazel::tools::cpp::runfiles::Runfiles;
namespace fs = std::filesystem;

// Path manipulation utilities
namespace path {

// Normalize a path (remove "../" and "." components)
std::string normalize(const std::string &p) {
  return fs::path(p).lexically_normal().generic_string();
}

// Remove prefix from path
std::string relativize(const std::string &path, const std::string &prefix) {
  if (path.size() >= prefix.size() && path.compare(0, prefix.size(), prefix) == 0) {
    size_t start = prefix.size();
    if (start < path.size() && path[start] == '/') {
      start++;
    }
    return path.substr(start);
  }
  return path;
}

bool starts_with(const std::string &str, const std::string &prefix) {
  return str.size() >= prefix.size() && str.compare(0, prefix.size(), prefix) == 0;
}

}  // namespace path

struct FileEntry {
  std::string short_path;
  std::string disk_path;

  // Parse a file entry in "short_path=disk_path" format
  static FileEntry parse(const std::string &line) {
    FileEntry entry;
    size_t eq = line.find('=');
    if (eq == std::string::npos) {
      std::cerr << "ERROR: Invalid file entry (no '='): " << line << std::endl;
      std::exit(1);
    }

    entry.short_path = line.substr(0, eq);
    entry.disk_path = line.substr(eq + 1);

    return entry;
  }
};

// Get path inside the zip where a file should go
std::string get_zip_runfiles_path(const std::string &path, const std::string &workspace_name,
                                  bool legacy_external_runfiles) {
  std::string zip_runfiles_path;

  if (legacy_external_runfiles && path::starts_with(path, "external/")) {
    zip_runfiles_path = path::relativize(path, "external");
  } else {
    // Normalize workspace_name/../external/path to external/path
    std::string combined = workspace_name + "/" + path;
    zip_runfiles_path = path::normalize(combined);
  }

  return "runfiles/" + zip_runfiles_path;
}

// Check if an executable exists in runfiles, accounting for Windows file extensions.
// Returns the path if found, otherwise an empty string.
std::string find_executable_in_runfiles(Runfiles *runfiles, const std::string &runfile_path) {
  std::string path = runfiles->Rlocation(runfile_path);
  if (path.empty()) {
    return "";
  }

#ifndef _WIN32
  if (std::filesystem::exists(path)) {
    return path;
  }
#else
  // On Windows, try common executable extensions
  std::string path_with_ext;
  const std::vector<std::string> extensions = {".exe", ".bat", ".cmd"};
  for (const auto &ext : extensions) {
    path_with_ext = path + ext;
    if (std::filesystem::exists(path_with_ext)) {
      return path_with_ext;
    }
  }
#endif

  return "";  // Not found
}

struct Config {
  std::string output;
  std::string workspace_name;
  std::string main_file;
  std::string repo_mapping_manifest;
  bool legacy_external_runfiles = false;
  std::string input_files_manifest;
};

Config parse_args(int argc, char *argv[]) {
  if (argc < 2) {
    std::cerr << "Usage: " << argv[0] << " [flags...] <input_files_manifest>" << std::endl;
    std::exit(1);
  }

  Config config;

  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];

    if (arg == "--output") {
      if (i + 1 >= argc) {
        std::cerr << "ERROR: --output requires a value" << std::endl;
        std::exit(1);
      }
      config.output = argv[++i];
    } else if (arg == "--workspace-name") {
      if (i + 1 >= argc) {
        std::cerr << "ERROR: --workspace-name requires a value" << std::endl;
        std::exit(1);
      }
      config.workspace_name = argv[++i];
    } else if (arg == "--main-file") {
      if (i + 1 >= argc) {
        std::cerr << "ERROR: --main-file requires a value" << std::endl;
        std::exit(1);
      }
      config.main_file = argv[++i];
    } else if (arg == "--repo-mapping-manifest") {
      if (i + 1 >= argc) {
        std::cerr << "ERROR: --repo-mapping-manifest requires a value" << std::endl;
        std::exit(1);
      }
      config.repo_mapping_manifest = argv[++i];
    } else if (arg == "--legacy-external-runfiles") {
      config.legacy_external_runfiles = true;
    } else {
      config.input_files_manifest = arg;
    }
  }

  return config;
}

std::vector<FileEntry> read_input_manifest(const std::string &manifest_path) {
  std::vector<FileEntry> files;
  std::ifstream in(manifest_path);

  if (!in) {
    std::cerr << "ERROR: Cannot open input files manifest: " << manifest_path << std::endl;
    std::exit(1);
  }

  std::string line;
  while (std::getline(in, line)) {
    if (!line.empty()) {
      files.push_back(FileEntry::parse(line));
    }
  }

  return files;
}

void validate_config(const Config &config) {
  if (config.input_files_manifest.empty()) {
    std::cerr << "ERROR: No input files manifest specified" << std::endl;
    std::exit(1);
  }
  if (config.output.empty()) {
    std::cerr << "ERROR: --output is required" << std::endl;
    std::exit(1);
  }
  if (config.workspace_name.empty()) {
    std::cerr << "ERROR: --workspace-name is required" << std::endl;
    std::exit(1);
  }
  if (config.main_file.empty()) {
    std::cerr << "ERROR: --main-file is required" << std::endl;
    std::exit(1);
  }
}

void write_zip_manifest(const Config &config, const std::vector<FileEntry> &files,
                        const std::string &manifest_path) {
  // Open in binary mode to avoid LF -> CRLF conversion on Windows.
  std::ofstream manifest(manifest_path, std::ios::binary);
  if (!manifest) {
    std::cerr << "ERROR: Cannot create manifest file: " << manifest_path << std::endl;
    std::exit(1);
  }

  manifest << "__main__.py=" << config.main_file << "\n";

  manifest << "__init__.py=\n";
  manifest << get_zip_runfiles_path("__init__.py", config.workspace_name,
                                    config.legacy_external_runfiles)
           << "=\n";

  for (const auto &file : files) {
    std::string zip_path = get_zip_runfiles_path(file.short_path, config.workspace_name,
                                                 config.legacy_external_runfiles);
    manifest << zip_path << "=" << file.disk_path << "\n";
  }

  if (!config.repo_mapping_manifest.empty()) {
    manifest << "runfiles/_repo_mapping=" << config.repo_mapping_manifest << "\n";
  }
}

void run_zipper(const std::string &executable, const std::string &output,
                const std::string &manifest_path) {
  std::string error;
  std::unique_ptr<Runfiles> runfiles(Runfiles::Create(executable, &error));

  if (runfiles == nullptr) {
    std::cerr << "ERROR: Failed to initialize runfiles: " << error << std::endl;
    std::exit(1);
  }

  std::string zipper_path =
      find_executable_in_runfiles(runfiles.get(), "bazel_tools/tools/zip/zipper/zipper");
  if (zipper_path.empty()) {
    // @bazel_tools/tools/zip:zipper is an alias for @bazel_tools/third_party/ijar:zipper.
    // On some systems, this means the binary is located in bazel_tools/third_party/ijar/zipper
    // instead.
    zipper_path =
        find_executable_in_runfiles(runfiles.get(), "bazel_tools/third_party/ijar/zipper");
    if (zipper_path.empty()) {
      std::cerr << "ERROR: Could not locate zipper in runfiles" << std::endl;
      std::exit(1);
    }
  }

  std::string cmd = zipper_path + " cC " + output + " @" + manifest_path;
  int result = std::system(cmd.c_str());

  if (result != 0) {
    std::cerr << "ERROR: zipper failed with exit code " << result << std::endl;
    std::exit(1);
  }
}

int main(int argc, char *argv[]) {
  Config config = parse_args(argc, argv);
  validate_config(config);

  std::vector<FileEntry> files = read_input_manifest(config.input_files_manifest);

  std::string zip_manifest_path = config.output + ".manifest.txt";
  write_zip_manifest(config, files, zip_manifest_path);
  run_zipper(argv[0], config.output, zip_manifest_path);

  return 0;
}
