import 'dart:ui' show Brightness;

const String _assetRoot = 'assets/icons/catppuccin';
const String _fallbackFileIcon = '_file';
const String _fallbackFolderIcon = '_folder';

const Map<String, String> _fileNameIcons = <String, String>{
  'cmakelists.txt': 'cmake',
  'makefile': 'makefile',
  '.gitignore': 'git',
  '.gitattributes': 'git',
  '.gitmodules': 'git',
  'nuget.config': 'nuget',
};

const Map<String, String> _filePrefixIcons = <String, String>{
  'readme': 'readme',
  'license': 'license',
  'notice': 'license',
  'copying': 'license',
  'changelog': 'changelog',
};

const Map<String, String> _extensionIcons = <String, String>{
  'c': 'c',
  'cpp': 'cpp',
  'cc': 'cpp',
  'cxx': 'cpp',
  'c++': 'cpp',
  'cp': 'cpp',
  'h': 'c-header',
  'hpp': 'cpp-header',
  'hh': 'cpp-header',
  'hxx': 'cpp-header',
  'h++': 'cpp-header',
  'inl': 'cpp-header',
  'ipp': 'cpp-header',
  'tcc': 'cpp-header',
  'ixx': 'cpp',
  'cppm': 'cpp',
  'ccm': 'cpp',
  'cxxm': 'cpp',
  'c++m': 'cpp',
  'mxx': 'cpp',
  'mpp': 'cpp',
  'lib': 'lib',
  'dll': 'lib',
  'md': 'markdown',
  'yaml': 'yaml',
  'yml': 'yaml',
  'json': 'json',
  'xml': 'xml',
  'txt': 'text',
  'toml': 'toml',
  'png': 'image',
  'jpg': 'image',
  'jpeg': 'image',
  'gif': 'image',
  'ico': 'image',
  'webp': 'image',
  'bmp': 'image',
  'svg': 'svg',
  'zip': 'zip',
  'rar': 'zip',
  '7z': 'zip',
  'tar': 'zip',
  'gz': 'zip',
  'pdf': 'pdf',
  'sln': 'visual-studio',
  'vcxproj': 'visual-studio',
  'vcxitems': 'visual-studio',
  'csproj': 'visual-studio',
  'nupkg': 'nuget',
  'ps1': 'powershell',
  'bat': 'batch',
  'cmd': 'batch',
  'dart': 'dart',
  'py': 'python',
  'pyw': 'python',
  'pyi': 'python',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'esx': 'javascript',
  'f': 'fortran',
  'for': 'fortran',
  'f77': 'fortran',
  'f90': 'fortran',
  'f95': 'fortran',
  'f03': 'fortran',
  'f08': 'fortran',
  'll': 'llvm',
  'bc': 'llvm',
  'vbs': 'visual-studio',
  'pdb': 'database',
  'asm': 'assembly',
  's': 'assembly',
  'nasm': 'assembly',
  'java': 'java',
  'jsp': 'java',
  'class': 'java-class',
  'jar': 'java-jar',
  'cs': 'csharp',
  'csx': 'csharp',
  'rs': 'rust',
  'ron': 'rust',
  'html': 'html',
  'htm': 'html',
  'xhtml': 'html',
  'css': 'css',
  'scss': 'sass',
  'sass': 'sass',
  'less': 'less',
  'xaml': 'xaml',
  'axaml': 'xaml',
  'db': 'database',
  'sql': 'database',
  'sqlite': 'database',
  'sqlite3': 'database',
  'exe': 'exe',
  'msi': 'exe',
};

const Map<String, String> _directoryIcons = <String, String>{
  'include': 'folder_include',
  'includes': 'folder_include',
  'src': 'folder_src',
  'source': 'folder_src',
  'sources': 'folder_src',
  'code': 'folder_src',
  'lib': 'folder_lib',
  'libs': 'folder_lib',
  'test': 'folder_tests',
  'tests': 'folder_tests',
  'spec': 'folder_tests',
  'docs': 'folder_docs',
  'doc': 'folder_docs',
  'assets': 'folder_assets',
  'images': 'folder_images',
  'img': 'folder_images',
  'icons': 'folder_images',
  'scripts': 'folder_scripts',
  'config': 'folder_config',
  'cfg': 'folder_config',
  'conf': 'folder_config',
  'settings': 'folder_config',
  'dist': 'folder_dist',
  'release': 'folder_dist',
  'bin': 'folder_dist',
  'windows': 'folder_windows',
  'shared': 'folder_shared',
  'utils': 'folder_utils',
  'themes': 'folder_themes',
};

/// 解析文件/目录对应的 catppuccin 图标资产路径。
///
/// 文件按「文件名精确匹配 > 名称前缀匹配 > 扩展名匹配 > `_file` 兜底」查找，
/// 目录按名称匹配、未知目录回退 `_folder`，展开态追加 `_open`；
/// 主题亮度为 [Brightness.dark] 时使用 mocha，否则使用 latte。
String iconAssetFor({
  required Brightness brightness,
  required String name,
  bool isDirectory = false,
  bool isExpanded = false,
}) {
  final String flavor = brightness == Brightness.dark ? 'mocha' : 'latte';
  final String icon = isDirectory
      ? _directoryIcon(name, isExpanded)
      : _fileIcon(name);
  return '$_assetRoot/$flavor/$icon.svg';
}

String _directoryIcon(String name, bool isExpanded) {
  final String base =
      _directoryIcons[name.toLowerCase()] ?? _fallbackFolderIcon;
  return isExpanded ? '${base}_open' : base;
}

String _fileIcon(String name) {
  final String lower = name.toLowerCase();
  return _fileNameIcons[lower] ??
      _prefixIcon(lower) ??
      _extensionIcons[_extensionOf(lower)] ??
      _fallbackFileIcon;
}

String? _prefixIcon(String lowerName) {
  for (final MapEntry<String, String> entry in _filePrefixIcons.entries) {
    if (lowerName.startsWith(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

String _extensionOf(String lowerName) {
  final int dot = lowerName.lastIndexOf('.');
  if (dot <= 0 || dot == lowerName.length - 1) {
    return '';
  }
  return lowerName.substring(dot + 1);
}
