# -*- coding: utf-8 -*-

# Copyright 2019 Google LLC
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

import os
import sys
import shutil
from typing import List


def log(s):
    print(s, file=sys.stderr, flush=True)


def remove_duplicates(elements):
    seen_elements = set()
    new_elements = []
    for element in elements:
        if element not in seen_elements:
            new_elements.append(element)
            seen_elements.add(element)
    return new_elements


def main():
    elements = os.environ["PATH"].split(os.pathsep)  # type: List[str]
    elements = remove_duplicates(elements)

    limit = 10000

    for command in sys.argv[1:]:
        log("Considering " + command)
        command_path = shutil.which(command, path=os.pathsep.join(elements))
        while command_path:

            # Don't loop forever.
            limit -= 1
            if limit <= 0:
                print("loop limit")
                sys.exit(1)

            log("Has command_path: " + command_path)

            for i in range(len(elements)):
                new_elements = elements[:i] + elements[i+1:]
                new_command_path = shutil.which(command, path=os.pathsep.join(new_elements))
                if new_command_path != command_path:
                    elements = new_elements
                    command_path = new_command_path
                    break
    print(os.pathsep.join(elements))


if __name__ == '__main__':
    main()
