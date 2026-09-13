"""OpenVINO 配方 ensure_unpacked 的解压标记绑定驱动（无需联网）。

首次解压 → 同名复用 → 归档换名后重解压，覆盖 .complete 标记与归档身份的绑定。
由 test/build/library_build_openvino_test.dart 在临时目录以真实 Python 执行。
"""

import importlib
import os
import zipfile

work = os.getcwd()
src = os.path.join(work, 'src')
os.makedirs(src, exist_ok=True)

# 配方在 import 时读取 SRC_PATH/BUILD_OUT，先注入再导入。
os.environ['SRC_PATH'] = src
os.environ['BUILD_OUT'] = os.path.join(work, 'out')

import build as recipe


def make_archive(name, marker):
    path = os.path.join(work, name)
    with zipfile.ZipFile(path, 'w') as package:
        package.writestr('payload.txt', marker)
    return path


first = make_archive('pkg-1.zip', 'first')
print('first_return=%s' % recipe.ensure_unpacked(first))
recipe = importlib.reload(recipe)
recipe.ensure_unpacked(first)
print('reuse_done')

second = make_archive('pkg-2.zip', 'second')
print('second_return=%s' % recipe.ensure_unpacked(second))
