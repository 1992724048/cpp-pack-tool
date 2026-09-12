const List<String> msbuildMacroKeys = <String>[
  'Configuration',
  'Platform',
  'OutDir',
  'IntDir',
  'TargetDir',
  'TargetPath',
  'TargetName',
  'TargetExt',
  'ProjectDir',
  'SolutionDir',
  'MSBuildThisFileDirectory',
];

String macroEnvName(String macroKey) => 'CNP_$macroKey';
