# Required.
# docker build -f baseimages/docker-cli/Windows.Dockerfile -t docker .

ARG WINDOWS_IMAGE=microsoft/windowsservercore:ltsc2019
FROM $WINDOWS_IMAGE as environment

# set the default shell as powershell.
# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324 
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# install MinGit (especially for "go get" and docker build by git repos) 
ENV GIT_VERSION 2.17.1
ENV GIT_TAG v${GIT_VERSION}.windows.1
ENV GIT_DOWNLOAD_URL https://github.com/git-for-windows/git/releases/download/${GIT_TAG}/MinGit-${GIT_VERSION}-64-bit.zip
ENV GIT_DOWNLOAD_SHA256 668d16a799dd721ed126cc91bed49eb2c072ba1b25b50048280a4e2c5ed56e59
RUN Write-Host ('Downloading {0} ...' -f $env:GIT_DOWNLOAD_URL); \
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
	Invoke-WebRequest -Uri $env:GIT_DOWNLOAD_URL -OutFile 'git.zip'; \	
	\
	Write-Host 'Expanding ...'; \
	Expand-Archive -Path git.zip -DestinationPath C:\git\.; \
	\
	Write-Host 'Removing ...'; \
	Remove-Item git.zip -Force; \
	\
	Write-Host 'Updating PATH ...'; \
	$env:PATH = 'C:\git\cmd;C:\git\mingw64\bin;C:\git\usr\bin;' + $env:PATH; \
	[Environment]::SetEnvironmentVariable('PATH', $env:PATH, [EnvironmentVariableTarget]::Machine); \
	\
	Write-Host 'Verifying install ...'; \
	Write-Host 'git --version'; git --version; \
	\
	Write-Host 'Complete.';

# ideally, this would be C:\go to match Linux a bit closer, but C:\go is the recommended install path for Go itself on Windows
ENV GOPATH C:\\gopath

# PATH isn't actually set in the Docker image, so we have to set it from within the container
RUN $newPath = ('{0}\bin;C:\go\bin;{1}' -f $env:GOPATH, $env:PATH); \
	Write-Host ('Updating PATH: {0}' -f $newPath); \
	[Environment]::SetEnvironmentVariable('PATH', $newPath, [EnvironmentVariableTarget]::Machine);

# install go lang
# ideally we should be able to use FROM golang:windowsservercore-1803. This is not done due to two reasons
# 1. The go lang for 1803 tag is not available.
# 2. The image pulls 2.11.1 version of MinGit which has an issue with git submodules command. https://github.com/git-for-windows/git/issues/1007#issuecomment-384281260 

ENV GOLANG_VERSION 1.10.3

RUN $url = ('https://golang.org/dl/go{0}.windows-amd64.zip' -f $env:GOLANG_VERSION); \
	Write-Host ('Downloading {0} ...' -f $url); \
	Invoke-WebRequest -Uri $url -OutFile 'go.zip'; \
	\
	$sha256 = 'a3f19d4fc0f4b45836b349503e347e64e31ab830dedac2fc9c390836d4418edb'; \
	Write-Host ('Verifying sha256 ({0}) ...' -f $sha256); \
	if ((Get-FileHash go.zip -Algorithm sha256).Hash -ne $sha256) { \
		Write-Host 'FAILED!'; \
		exit 1; \
	}; \
	\
	Write-Host 'Expanding ...'; \
	Expand-Archive go.zip -DestinationPath C:\; \
	\
	Write-Host 'Verifying install ("go version") ...'; \
	go version; \
	\
	Write-Host 'Removing ...'; \
	Remove-Item go.zip -Force; \
	\
	Write-Host 'Complete.';

# Build the docker executable
FROM environment as dockercli
ARG DOCKER_CLI_LKG_COMMIT=c98c4080a323fb0e4fdf7429d8af4e2e946d09b5
WORKDIR \\gopath\\src\\github.com\\docker\\cli
RUN git clone https://github.com/docker/cli.git \gopath\src\github.com\docker\cli; \
    git checkout $env:DOCKER_CLI_LKG_COMMIT; \
    scripts\\make.ps1 -Binary -ForceBuildAll

# setup the runtime environment
FROM environment as runtime
COPY --from=dockercli /gopath/src/github.com/docker/cli/build/docker.exe c:/docker/docker.exe
RUN setx /M PATH $('c:\docker;{0}' -f $env:PATH);
ENTRYPOINT [ "docker.exe" ]
CMD [ "--help" ]