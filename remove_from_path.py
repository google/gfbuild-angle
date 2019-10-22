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

path = os.environ["PATH"].split(os.pathsep)  # type: List[str]
for command in sys.argv:
    command_path = shutil.which(command, path=os.pathsep.join(path))
    while command_path:
        for i in range(len(path)):
            new_path = path[:i] + path[i+1:]
            new_command_path = shutil.which(command, path=os.pathsep.join(new_path))
            if new_command_path != command_path:
                path = new_path
                command_path = new_command_path
                break
print(os.pathsep.join(path))
