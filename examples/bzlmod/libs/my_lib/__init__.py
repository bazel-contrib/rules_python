# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import websockets


def websockets_is_for_python_version(sanitized_version_check):
    # We are checking that the name of the repository folders
    # match the expected generated names. If we update the folder
    # structure or naming we will need to modify this test.
    #
    # The wheels downloaded with the bazel downloader are extracted in a
    # repository named after the wheel filename, which has the python tag.
    wants = [
        f"_{sanitized_version_check}_websockets",
        f"_cp{sanitized_version_check}_cp{sanitized_version_check}",
    ]
    got_full = websockets.__file__
    if not any(want in got_full for want in wants):
        print(f"Failed, expected one of {wants} to be a substring of '{got_full}'.")
        return False

    return True
