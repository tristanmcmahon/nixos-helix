{ python3Packages }:

python3Packages.buildPythonApplication {
  pname = "hamllm";
  version = "0.1.0";
  pyproject = true;
  src = ../vendor/hamllm;

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  pythonImportsCheck = [ "hamllm" ];
}
