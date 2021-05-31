# -*- coding: utf-8 -*-

# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import sys

from pathlib import Path

VK_GL_CTS_DEP = """
  'third_party/VK-GL-CTS/src': {
    'url': '{chromium_git}/external/github.com/KhronosGroup/VK-GL-CTS@{vk_gl_cts_revision}',
  },
"""


def log(s):
    print(s, file=sys.stderr, flush=True)


def main():
    log("Reading DEPS.")
    text = Path("DEPS").read_text(encoding="utf-8", errors="ignore")
    log("Replacing large dependencies that we don't need.")
    text = text.replace(VK_GL_CTS_DEP, "")
    log("Writing updated DEPS file.")
    Path("DEPS").write_text(text, encoding="utf-8", errors="ignore")


if __name__ == '__main__':
    main()
