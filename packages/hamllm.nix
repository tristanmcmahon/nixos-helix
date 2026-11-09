{ python3Packages }:

python3Packages.buildPythonApplication {
  pname = "hamllm";
  version = "0.2.1";
  pyproject = true;
  src = ../vendor/hamllm;

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  pythonImportsCheck = [ "hamllm" ];
}
