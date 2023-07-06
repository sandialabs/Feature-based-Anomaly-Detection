right_after_pull_docker_image=$(date +%s)
cat /etc/os-release || echo "cat /etc/os-release failed."
lsb_release -a || echo "lsb_release -a failed."
hostnamectl || echo "hostnamectl failed."
uname -r || echo "uname -r failed."
uname --all || echo "uname --all failed."

    # ps $$ || echo "ps not found." Unfortunately, we cannot use ps because ps can leak secrets (in surprising ways). For example, ps inside a Dockerfile will print the ps of the host, including the /kaniko/exector being run, including all --build-args.
echo $SHELL
echo $0
readlink /proc/$$/exe
echo $(whoami)
echo $USER


if ! [ -z ${GITLAB_CI+ABC} ]; then
set -o errexit
fi


if [ -z ${CI_SERVER_HOST+ABC} ]; then
CI_SERVER_HOST=cee-gitlab.sandia.gov
fi

    # If we need to apk add openssh-client, then we will need HTTPS_PROXY set first.
    # This potentially leads to a problem if we need SSH to access the ETC_ENVIRONMENT_LOCATION.
    # The ETC_ENVIRONMENT_LOCATION is not generally intended for secret keys like the SSH_PRIVATE_DEPLOY_KEY.
if [ -z ${ETC_ENVIRONMENT_LOCATION+ABC} ]; then
ETC_ENVIRONMENT_LOCATION=https://$CI_SERVER_HOST/shell-bootstrap-scripts/network-settings/-/raw/master/set_variables_in_CI.sh
echo "ETC_ENVIRONMENT_LOCATION was unset, so trying $ETC_ENVIRONMENT_LOCATION."
fi

    # All of this will be skipped unless you set ETC_ENVIRONMENT_LOCATION in GitLab.
    # Note that this will not be skipped if ETC_ENVIRONMENT_LOCATION is set to empty;
    # you could set ETC_ENVIRONMENT_LOCATION to empty for some special behavior, but you're on your own there.
if [ -z ${ETC_ENVIRONMENT_LOCATION} ]; then echo "ETC_ENVIRONMENT_LOCATION is set to the empty string; I hope you know why, because I certainly do not."; fi


    # Why do we need a URL to find a script that will run these very commands? We don't...unless we need to pass the location of the script to a job that uses before_script for something else, and thus cannot inherit from this job.
    # In that case, we can run a prior job that does inherit from this job and sets artifacts:reports:dotenv.
if [ -z ${FIX_ALL_GOTCHAS_SCRIPT_LOCATION+ABC} ]; then
FIX_ALL_GOTCHAS_SCRIPT_LOCATION=https://$CI_SERVER_HOST/shell-bootstrap-scripts/shell-bootstrap-scripts/-/raw/master/fix_all_gotchas.sh
fi


    # Strictly speaking, this serves the same function as .profile, being run before everything else.
    # You *could* put arbitrary shell commands in the file, but the intended purpose is
    # to save on manual work by allowing you to set only one GitLab variable that points
    # to more variables to set.
    # Special note if the environment file is used to set up a proxy with HTTPS_PROXY...
    # $ETC_ENVIRONMENT_LOCATION must be a location that we can access *before* setting up the proxy variables.
echo "ETC_ENVIRONMENT_LOCATION = $ETC_ENVIRONMENT_LOCATION"

    # We do not want the script to hang waiting for a password if the private key is rejected.
mkdir -p $HOME/.ssh

    # mkdir --parents exists on all Linux including Alpine, but not on Mac.
echo "PasswordAuthentication=no" >> ~/.ssh/config


    # The BusyBox version of wget pays attention to http_proxy, but not no_proxy, a dangerous combination.
    # The BusyBox version of wget permits a special option --proxy off to ignore http_proxy.
    # Note the difference from --no-proxy used by GNU wget.
    # Strangely, it seems that if you pass --proxy off to GNU wget, it fails (so the next command in the chain gets executed) but the file is still downloaded.
    # The next wget in the sequence, if it has --no-clobber, will also fail on GNU wget.
    # To work around this, we don't have --no-clobber on the second wget.
    # If necessary we use --no-check-certificate, because the network settings will have a list of servers to whitelist,
    # but we cannot have the list of servers to trust the certificates of before we download it.
    # Effectively, we are hardcoding a one-off automatic trust of ETC_ENVIRONMENT_LOCATION itself.
echo $SSL_CERT_DIR
ls environment.sh || (wget --proxy off $ETC_ENVIRONMENT_LOCATION --output-document environment.sh --no-clobber && echo "Successfully downloaded $ETC_ENVIRONMENT_LOCATION using wget!") || (strace -e openat wget --proxy off $ETC_ENVIRONMENT_LOCATION --output-document environment.sh) || (wget --no-proxy $ETC_ENVIRONMENT_LOCATION --output-document environment.sh && echo "Successfully downloaded $ETC_ENVIRONMENT_LOCATION using wget!") || (wget --no-proxy --no-check-certificate $ETC_ENVIRONMENT_LOCATION --output-document environment.sh && echo "Successfully downloaded $ETC_ENVIRONMENT_LOCATION using wget!") || (wget --help && wget $ETC_ENVIRONMENT_LOCATION --output-document environment.sh) || curl --verbose $ETC_ENVIRONMENT_LOCATION --output environment.sh || curl --verbose --location $ETC_ENVIRONMENT_LOCATION --output environment.sh || (echo $SSH_PRIVATE_DEPLOY_KEY > SSH.PRIVATE.KEY && scp -i SSH.PRIVATE.KEY $ETC_ENVIRONMENT_LOCATION environment.sh && rm SSH.PRIVATE.KEY)

    # Make sure to clean up that rm SSH.PRIVATE.KEY in case we want to use this script when building a Docker image.
cat environment.sh

    # If the environment file wants to hack on our PATH, we usually want to ignore that part.
SAVED_PATH=$PATH
set -o allexport

    # image gcr.io/kaniko-project/executor:debug (BusyBox v1.31.1) chokes on source environment.sh and also inexplicably chokes on the if-statement or ||
    # - if source environment.sh; then true; else . ./environment.sh; fi
. ./environment.sh
set +o allexport
PATH=$SAVED_PATH


    # We'll usually connect to this machine using the loopback IP 127.0.0.1, but just in case some program tries to connect to its public IP address, we want to be sure that won't go through the proxy, if any.
if hostname -i; then
no_proxy="$(hostname -i),$no_proxy"
fi


    # Most applications take http_proxy, but a few pointedly take HTTP_PROXY.
    # We could have an || here of an enumerated list of applications that want HTTP_PROXY.
    # Alternatively, we could always set HTTP_PROXY, but most of the time that would unnecessarily pollute the namespace.
    # Hmm.
if command -v sdkmanager && ! [ -z ${http_proxy+ABC} ]; then
HTTP_PROXY=$http_proxy
fi


    # Fedora appears to ignore http_proxy, even though it's supposed to respect http_proxy
if [ $(id -u) -eq 0 ] && ls /etc/dnf/dnf.conf && grep Fedora /etc/os-release && ! [ -z ${http_proxy+ABC} ]; then
echo "proxy=$http_proxy" >> /etc/dnf/dnf.conf
cat /etc/dnf/dnf.conf
fi


    # If we can't reach any of the package repositories from here, then we want to disable them.
if dnf config-manager --help && false; then

    #   Unfortunately, dnf does not seem to provide any way to individually health-check package repositories.
    #   The first entry from repolist will be the table header 'repo'.
REPO_NAMES=$(dnf repolist --enabled | cut -d ' ' -f 1 | tr '\n' ' ' | cut -d ' ' -f '2-')
for REPO_NAME in $REPO_NAMES; do

    #     dnf check-update will not work for this because dnf check-update returns an error code on success
    #     https://dnf.readthedocs.io/en/latest/command_ref.html#check-update-command
    #     DNF exit code will be 100 when there are updates available and a list of the updates will be printed, 0 if not and 1 if an error occurs
if ! dnf check-update; then
if ! [ -z ${PREVIOUS_DISABLED_REPO+ABC} ]; then
dnf config-manager --enable $PREVIOUS_DISABLED_REPO
fi
PREVIOUS_DISABLED_REPO=$REPO_NAME
dnf config-manager --disable $REPO_NAME
fi
done
dnf check-update
fi


if ! [ -z ${OS_PACKAGE_REPOSITORY_MIRROR+ABC} ]; then
if dnf config-manager --help; then
for REPONAME in AppStream BaseOS; do
if cat /etc/yum.repos.d/CentOS-Stream-${REPONAME}.repo; then
sed -i 's/mirrorlist/#mirrorlist' /etc/yum.repos.d/CentOS-Stream-${REPONAME}.repo
dnf config-manager --save --setopt=CentOS-Stream-${REPONAME}.baseurl=${OS_PACKAGE_REPOSITORY_MIRROR}/${REPONAME}/x86_64/os
if ! [ -z ${OS_PACKAGE_REPOSITORY_USERNAME+ABC} ]; then
dnf config-manager --save --setopt=CentOS-Stream-${REPONAME}.username=${OS_PACKAGE_REPOSITORY_USERNAME}
fi
if ! [ -z ${OS_PACKAGE_REPOSITORY_PASSWORD+ABC} ]; then
dnf config-manager --save --setopt=CentOS-Stream-${REPONAME}.password=${OS_PACKAGE_REPOSITORY_PASSWORD}
fi
fi
done
fi
fi
if [ -z ${OS_PACKAGE_REPOSITORY_URLS+ABC} ]; then
echo "OS_PACKAGE_REPOSITORY_URLS is unset, so assuming you do not need any non-default repositories set up."
else
OS_PACKAGE_REPOSITORY_URLS=${OS_PACKAGE_REPOSITORY_URLS//MAGIC_STRING_TO_REPLACE_SPACE/ }
for URL in $OS_PACKAGE_REPOSITORY_URLS; do
echo "$URL in $OS_PACKAGE_REPOSITORY_URLS"
    OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS=${URL#https://}
OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES=${OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS//\//_}
if ! echo $DNF_ADDED_REPOSITORY_NAMES | grep $OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES && command -v dnf && dnf config-manager --help; then
dnf config-manager --add-repo $URL
echo "OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES=$OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES"
DNF_ADDED_REPOSITORY_NAMES="$DNF_ADDED_REPOSITORY_NAMES $OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES"

    #       Some repository URLs already end in .repo, some do not and will have .repo added by dnf config-manager.
OS_PACKAGE_REPOSITORY_URL_WITH_REPO_SUFFIX=${OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES%.repo}.repo
if [ -f /etc/yum.repos.d/$OS_PACKAGE_REPOSITORY_URL_WITH_REPO_SUFFIX ]; then DNF_ADDED_REPOSITORY_FILES="$DNF_ADDED_REPOSITORY_FILES $OS_PACKAGE_REPOSITORY_URL_WITH_REPO_SUFFIX"; fi

    #       [^/] matches any character other than /, $ matches the end of the string
FILE_NAME_ONLY=$(echo $OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS | grep --only-matching '[^/]*$')
FILE_NAME_ONLY=${FILE_NAME_ONLY%.repo}.repo
if [ -f /etc/yum.repos.d/$FILE_NAME_ONLY ]; then DNF_ADDED_REPOSITORY_FILES="$DNF_ADDED_REPOSITORY_FILES $FILE_NAME_ONLY"; fi
if ! [ -z ${OS_PACKAGE_REPOSITORY_USERNAME+ABC} ]; then
dnf config-manager --save --setopt=${OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES}.username=${OS_PACKAGE_REPOSITORY_USERNAME}
fi
if ! [ -z ${OS_PACKAGE_REPOSITORY_PASSWORD+ABC} ]; then
dnf config-manager --save --setopt=${OS_PACKAGE_REPOSITORY_URL_WITHOUT_HTTPS_AND_SLASHES}.password=${OS_PACKAGE_REPOSITORY_PASSWORD}
fi
fi
if command -v yum-config-manager; then
yum-config-manager --add-repo $URL
fi
done
cat /etc/dnf/dnf.conf || echo "/etc/dnf/dnf.conf not found."
if ls /etc/yum.repos.d; then
echo "DNF_ADDED_REPOSITORY_NAMES=$DNF_ADDED_REPOSITORY_NAMES"
for REPO in $DNF_ADDED_REPOSITORY_FILES; do
cat /etc/yum.repos.d/$REPO
done
else
echo "/etc/yum.repos.d not found."
fi
fi


    # Trust certificate before handling SSH_PRIVATE_DEPLOY_KEY so that we can install OpenSSH if needed.
if [ -z ${PROXY_CA_PEM+ABC} ]; then
echo "PROXY_CA_PEM is unset, so assuming you do not need a merged CA certificate set up."
else

    # All of this will be skipped unless you set PROXY_CA_PEM in GitLab.
    # You will usually want to cat your.pem | xclip and paste it in as a File on GitLab.
    # See the KUBE_CA_PEM example at https://docs.gitlab.com/ee/ci/variables/README.html#variable-types
right_before_pull_cert=$(date +%s)
if [ ${#PROXY_CA_PEM} -ge 1024 ]; then
echo "The PROXY_CA_PEM filename looks far too long, did you set it as a Variable instead of a File?"

    # If it's the full certificate rather than a filename, write it to a file and save the file name.
echo "$PROXY_CA_PEM" > tmp-proxy-ca.pem

    # The quotes are very important here; echo $PROXY_CA_PEM will destroy the
    # newlines, and requests will (silently!) fail to parse the certificate,
    # leading to SSLError SSLCertVerificationError 'certificate verify failed self signed certificate in certificate chain (_ssl.c:1076)'
PROXY_CA_PEM=tmp-proxy-ca.pem
fi
# endif PROXY_CA_PEM looks like the contents are in a string
echo "PROXY_CA_PEM found at $(ls $PROXY_CA_PEM)"


    # With Alpine 3.13, apk add now uses https, and there doesn't appear to be any environment variable to tell apk to trust a certificate.
    # So we have to install the certificate into /etc/ssl/certs/ca-certificates.crt.
if [ $(id -u) -eq 0 ]; then
if command -v apk; then
apk add --no-cache ca-certificates --repository http://dl-cdn.alpinelinux.org/alpine/edge/main/ --allow-untrusted
fi
if command -v update-ca-certificates && [ $(stat -c '%u' /usr/local/share/ca-certificates/) -eq $(id -u) ]; then
ls /usr/local/share/ca-certificates/

    # http://manpages.ubuntu.com/manpages/hirsute/man8/update-ca-certificates.8.html
    # Certificates must have a .crt extension in order to be included by update-ca-certificates.
    # certificates with a .crt extension found below /usr/local/share/ca-certificates are also included as implicitly trusted.
cp -f $PROXY_CA_PEM /usr/local/share/ca-certificates/$PROXY_CA_PEM.crt || ls /usr/local/share/ca-certificates/$PROXY_CA_PEM.crt
update-ca-certificates
else
# if update-ca-certificates unavailable
if command -v update-ca-trust; then
ls /etc/pki/ca-trust/source/anchors/
cp $PROXY_CA_PEM /etc/pki/ca-trust/source/anchors/
update-ca-trust
else
# if update-ca-trust unavailable
if ls /etc/ssl/certs/ca-certificates.crt; then

    # We have a chicken-and-egg problem.
    # We cannot apk add ca-certificates because we need to trust the certificate first,
    # and we cannot trust the certificate because we need update-ca-certificates.
    # So we manually paste the certificate into /etc/ssl/certs/ca-certificates.crt.
    # This is a no good very bad thing and you should never do it.
PROXY_CA_PEM_NUM_LINES=$(wc -l < $PROXY_CA_PEM)
if [ $PROXY_CA_PEM_NUM_LINES -lt 8 ] || [ $PROXY_CA_PEM_NUM_LINES -gt 128 ]; then
echo "PROXY_CA_PEM_NUM_LINES is $PROXY_CA_PEM_NUM_LINES, something is terribly wrong."
false
fi

    # We don't want to add it to the end if we already added it to the end.
    # To the greatest extent possibly, this script should be idempotent.
if [ "$(tail -n $PROXY_CA_PEM_NUM_LINES /etc/ssl/certs/ca-certificates.crt)" != "$(cat $PROXY_CA_PEM)" ]; then
cat $PROXY_CA_PEM >> /etc/ssl/certs/ca-certificates.crt
if [ "$(tail -n $PROXY_CA_PEM_NUM_LINES /etc/ssl/certs/ca-certificates.crt)" != "$(cat $PROXY_CA_PEM)" ]; then false; fi
fi
# endif [ "$(tail -n $PROXY_CA_PEM_NUM_LINES /etc/ssl/certs/ca-certificates.crt)" != "$(cat $PROXY_CA_PEM)" ]
fi
# endif ls /etc/ssl/certs/ca-certificates.crt
fi
# endif command -v update-ca-trust else
fi
# endif command -v update-ca-certificates else
fi
# endif root
fi
# endif PROXY_CA_PEM

if [ -z ${SSH_PRIVATE_DEPLOY_KEY+ABC} ]; then echo "SSH_PRIVATE_DEPLOY_KEY is unset, so assuming you do not need SSH set up."; else

    # All of this will be skipped unless you set SSH_PRIVATE_DEPLOY_KEY as a variable
if [ ${#SSH_PRIVATE_DEPLOY_KEY} -le 5 ]; then echo "SSH_PRIVATE_DEPLOY_KEY looks far too short, something is wrong"; fi
if command -v ssh; then echo "Something that looks like ssh is already installed."; else
right_before_install_ssh=$(date +%s)
apk add openssh-client || (sed -i -e 's/https/http/' /etc/apk/repositories && apk add openssh-client) || apt-get install --assume-yes openssh-client || (apt-get update && apt-get install --assume-yes openssh-client) || dnf install --assumeyes openssh-clients || yum install --assumeyes openssh-clients || echo "Failed to install openssh-client; proceeding anyway to see if this image has its own SSH."
echo "adding openssh-client took $(( $(date +%s) - right_before_install_ssh)) seconds"
fi


    # ssh-agent -s starts the ssh-agent and then outputs shell commands to run.
    # ps -p $SSH_AGENT_PID does not always return an error code when e.g. -p is not supported on the host.
    # For unknown reasons, [ $(ps ax | grep [s]sh-agent | wc -l) -gt 0 ] reports the ssh-agent running when it is not.
if ! [ -z ${SSH_AUTH_SOCK+ABC} ]; then
echo "ssh-agent is already running."
else
eval $(ssh-agent -s)
fi


    ##
    ## Add the SSH key stored in SSH_PRIVATE_DEPLOY_KEY variable to the agent store.
    ## We're using tr to fix line endings which makes ed25519 keys work
    ## without extra base64 encoding.
    ## We use -d because the version of tr on alpine does not recognize --delete.
    ## https://gitlab.com/gitlab-examples/ssh-private-key/issues/1#note_48526556
    ##
if command -v ssh-add; then

    # https://stackoverflow.com/questions/27702452/loop-through-a-comma-separated-shell-variable
    #-   DEPLOY_KEYS_ONE_LINE=${SSH_PRIVATE_DEPLOY_KEY//$'\n'/MAGICSTRINGTOREPLACELINEFEED}
    # String substitution segfaults since Alpine 3.13: https://gitlab.alpinelinux.org/alpine/aports/-/issues/13469
DEPLOY_KEYS_ONE_LINE=$(printf -- "$SSH_PRIVATE_DEPLOY_KEY" | tr '$\n' '\r' | sed 's/\r\r/\r/g' | sed 's/\r/MAGICSTRINGTOREPLACELINEFEED/g')
DEPLOY_KEYS_SPLIT=${DEPLOY_KEYS_ONE_LINE//PRIVATE KEY-----MAGICSTRINGTOREPLACELINEFEED-----BEGIN /PRIVATE KEY-----$'\n'-----BEGIN }
DEPLOY_KEYS_WITHOUT_SPACES=${DEPLOY_KEYS_SPLIT// /MAGIC_STRING_TO_REPLACE_SPACE}
for SINGLE_KEY_WITHOUT_SPACES in $DEPLOY_KEYS_WITHOUT_SPACES; do
SINGLE_KEY_WITH_SPACES=${SINGLE_KEY_WITHOUT_SPACES//MAGIC_STRING_TO_REPLACE_SPACE/ }
SINGLE_KEY_MULTIPLE_LINES=${SINGLE_KEY_WITH_SPACES//MAGICSTRINGTOREPLACELINEFEED/$'\n'}
echo "$SINGLE_KEY_MULTIPLE_LINES" | tr -d '\r' | ssh-add -
echo "Added the private SSH deploy key with public fingerprint $(ssh-add -l)"
done
echo "WARNING! If you use this script to build a Docker image (rather than just run tests), make sure to delete the deploy key(s) with ssh-add -D after installing the relevant repos."
else
echo "It appears that this system does not have ssh-add, and we already failed to install openssh-client. You specified a SSH_PRIVATE_DEPLOY_KEY, so...we're just hoping you don't actually need that on this image/job."
fi


    ##
    ## Sometimes we may want to install directly from a git repository.
    ## Using up-to-the-minute updates of dependencies in our own tests alerts
    ## us if something breaks with the latest version of a dependency, even if
    ## that dependency has not made a new release yet.
    ## In order to pip install directly from git repositories,
    ## we need to whitelist the public keys of the git servers.
    ## You may want to add more lines for the domains of any other git servers
    ## you want to install dependencies from (which may or may not include the
    ## server that hosts your own repo).
    ## Similarly, if you want to push to a secondary repo as part of your build
    ## (as how cookiecutter-pylibrary builds examples and
    ## pushes to python-nameless), ssh will need to be allowed to reach that
    ## server.
    ## https://docs.travis-ci.com/user/ssh-known-hosts/
    ## https://discuss.circleci.com/t/add-known-hosts-on-startup-via-config-yml-configuration/12022/2
    ## Unfortunately, there seems to be no way to use ssh-keyscan on a server
    ## that you can only reach through a proxy. Thus, a simple
    ## ssh-keyscan -t rsa github.com gitlab.com >> ~/.ssh/known_hosts
    ## will fail. As a workaround, I just grabbed their public keys now and
    ## included them. These might go stale eventually, I'm not sure.
    ##
mkdir --parents ~/.ssh
echo "# github.com:22 SSH-2.0-babeld-f345ed5d\n" >> ~/.ssh/known_hosts
echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==\n" >> ~/.ssh/known_hosts

    #- echo "# gitlab.com:22 SSH-2.0-OpenSSH_7.2p2 Ubuntu-4ubuntu2.8\n" >> ~/.ssh/known_hosts
    #- echo "gitlab.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9\n" >> ~/.ssh/known_hosts
    #- echo "# gitlab.com:22 SSH-2.0-OpenSSH_7.9p1 Debian-10+deb10u2\n" >> ~/.ssh/known_hosts
    #- echo "gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf\n" >> ~/.ssh/known_hosts
echo "|1|gUnFmBJdTVHCi8BPB+eahKScyK0=|S1G/eoosMThpDJkvUfwqPCbPAFI= ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=" >> $HOME/.ssh/known_hosts


fi
# endif SSH_PRIVATE_DEPLOY_KEY

    # When we get the environment file, it might have some servers for us to whitelist.
    # Alternatively, maybe there was no ETC_ENVIRONMENT_LOCATION
    # and SERVERS_TO_WHITELIST_FOR_SSH is just manually set as a GitLab variable.
    # If SSH_PRIVATE_DEPLOY_KEY is not set, then we will silently ignore SERVERS_TO_WHITELIST_FOR_SSH,
    # since without a key of some kind we cannot use SSH anyway.
    # This allows us to share around a common ETC_ENVIRONMENT_LOCATION that includes SERVERS_TO_WHITELIST_FOR_SSH,
    # even though only some people actually use SSH for anything.
if [ -z ${SERVERS_TO_WHITELIST_FOR_SSH+ABC} ] || [ -z ${SSH_PRIVATE_DEPLOY_KEY+ABC} ]; then echo "SERVERS_TO_WHITELIST_FOR_SSH and SSH_PRIVATE_DEPLOY_KEY are not both set, so assuming you do not need any servers whitelisted for SSH."; else
echo "SERVERS_TO_WHITELIST_FOR_SSH = $SERVERS_TO_WHITELIST_FOR_SSH"
mkdir --parents ~/.ssh
if command -v ssh-keyscan; then

    # Honestly I'd rather not use -H by default,
    # since the dubious security advantage of hashing *the hostname* of all things seems outweighed by the difficulty in determining whether you're trusting the hosts you think you are when inspecting known_hosts,
    # but it seems like sometimes SSH throws a fit and just says "Host key verification failed." if you don't have the -H version in known_hosts. (E.g. for GitLab.com; that one is currently hardcoded, but the value it's hardcoded to is obtained with -H, whereas if changed to the non-H version you get "Host key verification failed.")
    # sort -u prevents us from adding the host again if it is already there.
    # 2>&1 makes the comments, such as # github.com, go into the file when we pipe.
ssh-keyscan -H -t ed25519 $SERVERS_TO_WHITELIST_FOR_SSH 2>&1 | sort -u - $HOME/.ssh/known_hosts > tmp_hosts
mv tmp_hosts $HOME/.ssh/known_hosts
else
echo "SERVERS_TO_WHITELIST_FOR_SSH, but ssh-keyscan is not available and we already failed to install openssh-client, so...we're just hoping you don't actually need that on this image/job."
fi
# endif ssh-keyscan
fi
# endif SERVERS_TO_WHITELIST_FOR_SSH

if [ -z ${PYTHON_TO_USE+ABC} ]; then
echo "python --version"
(python --version && python -c "import sys; print(sys.version_info.major)") || echo "python is not found by that name."
if command -v python3 && (! command -v python || [ $(python -c "import sys; print(sys.version_info.major)") -lt 3 ]); then
echo "python3 --version"
python3 --version || echo "python3 is not found by that name."

    # sometimes get shopt: not found and it never works when you do have it
if command -v shopt; then
shopt -s expand_aliases

    #- alias python=python3
    # On thyrllan/android-sdk, command -v $PYTHON_TO_USE && $PYTHON_TO_USE -c "import sys; print(sys.version_info.major)"
    # crashes when using alias python=python3 with python: command not found.
    # But only when running . fix_all_gotchas.sh, not when running the single line from YAML.
fi

    # Setting python() as a shell function causes the output of eg $(python -c "import sys; print(sys.version_info.major)") to include the function call.
    # - 'python() {'
    # -   python3 "$@"
    # - '}'
    # - export -f python
echo "python --version"
(python --version && python -c "import sys; print(sys.version_info.major)") || echo "python is not found by that name."

    # aliases don't work. Functions don't work.
    # Screw it, if for some reason someone runs this script as root outside of CI it'll override their Python to be Python 3 like it should be anyway.
if ls /usr/bin/python && ls /usr/bin/python3 && [ $(id -u) -eq 0 ] && false; then
rm /usr/bin/python
ln -s /usr/bin/python3 /usr/bin/python
PYTHON_TO_USE=python
else
PYTHON_TO_USE=python3
fi
# endif just root-replace python
else
PYTHON_TO_USE=python
fi
# endif python is python2
else
if command -v python3 && ! command -v python; then
echo "python is not found by that name, but is found as python3."
PYTHON_TO_USE=python3
else
PYTHON_TO_USE=python
fi
# endif command -v python (and either python3 does not exist or python is Python 3)
fi
# endif PYTHON_TO_USE unset
echo "PYTHON_TO_USE=$PYTHON_TO_USE"


if command -v conda; then echo "command finds conda"; else echo "command does not find conda"; fi
if ! command -v conda && [ -d /opt/conda ] && /opt/conda/bin/conda --help; then
CONDA_DIR=/opt/conda
PATH=$PATH:$CONDA_DIR/bin

    # Now PATH will find conda's "activate" script.
if ! command -v conda; then false; fi
else
if [ -d /opt/conda ] && ! /opt/conda/bin/conda --help; then
echo "/opt/conda/bin/conda exists, but is broken."
fi
fi
# endif -d /opt/conda
    # disable automatic activation of test-env in favor of creating test-env on the fly below
    #- if command -v conda; then
    # Annoyingly, conda activate is not idempotent.
    # We have to avoid activating the env twice, else we will get an error.
    # When a conda env is activated, it sets $CONDA_DEFAULT_ENV to its own name.
    #- if [ "$CONDA_DEFAULT_ENV" = "test-env" ]; then echo "This image already has test-env activated.";
    #  else
    #- if conda env list | grep test-env; then
    #- if source activate test-env; then true; else echo "No conda env named test-env was found, so not activating any particular env."; fi
    #- else echo "We did not see test-env in conda env list. You would think we could simply try to activate test-env and pass if that returned false, but strangely, on some systems activate test-env kills the whole script when test-env does not exist, even though it's a condition in an if."
    #- fi # endif test-env in conda env list
    #- fi # endif test-env already activated
    #- else
    #- echo "conda was not found on this container"
    #- fi

if command -v pyenv; then
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
fi


    # If PROXY_CA_PEM is provided, we'll merge it with pip's cert store.
    # In case pip gets upgraded later in the build,
    # we would like to upgrade pip first before messing with the internals of pip,
    # but it's a chicken-and-egg problem because
    # we need to set REQUESTS_CA_BUNDLE before we can use pip.

if [ -z ${PROXY_CA_PEM+ABC} ]; then
echo "PROXY_CA_PEM is unset, so assuming you do not need a merged CA certificate set up."
else


if command -v wget; then
right_before_set_up_wget=$(date +%s)

    # wget --version does not work with BusyBox wget
    # Does BusyBox wget pay attention to .wgetrc?
echo "ca_certificate=${PWD%/}/$PROXY_CA_PEM" > $HOME/.wgetrc
cat $HOME/.wgetrc
echo "Setting up wget took $(( $(date +%s) - right_before_set_up_wget)) seconds"
fi
if command -v curl; then
right_before_set_up_curl=$(date +%s)
ls /etc/ssl/certs/
cat $PROXY_CA_PEM > bundled.pem
if ls /etc/ssl/certs/ca-certificates.crt; then cat /etc/ssl/certs/ca-certificates.crt >> bundled.pem; fi
if ls /etc/ssl/certs/ca-bundle.crt; then cat /etc/ssl/certs/ca-bundle.crt >> bundled.pem; fi
if ls /etc/ssl/certs/ca-bundle.trust.crt; then cat /etc/ssl/certs/ca-bundle.trust.crt >> bundled.pem; fi

    # pwd might end in a / on some systems
    # We need to add a / if and only if pwd does not already end in a /.
echo "cacert=${PWD%/}/bundled.pem" > $HOME/.curlrc
cat $HOME/.curlrc
echo "Setting up curl took $(( $(date +%s) - right_before_set_up_curl)) seconds"
fi


if command -v conda; then
conda config --set proxy_servers.http $http_proxy
conda config --set proxy_servers.https $https_proxy
conda config --set ssl_verify $PROXY_CA_PEM
conda config --set remote_read_timeout_secs 60
fi
if command -v yarn; then
yarn config set cafile $PROXY_CA_PEM
fi
if command -v java; then
if [ -z ${JAVA_HOME+ABC} ]; then
JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 > /dev/null | grep 'java.home' | cut -d '=' -f 2 | cut -d ' ' -f 2)
echo "JAVA_HOME=$JAVA_HOME"
fi
if ! [ -z ${DOMAINS_TO_WHITELIST_FOR_SSL_SPACE_SEPARATED+ABC} ] && ls $JAVA_HOME/lib/security/cacerts; then
command -v openssl || apk add openssl || apt-get install --assume-yes openssl || dnf install --assumeyes openssl || yum install --assumeyes openssl || python2 /usr/bin/yum install --assumeyes openssl
ls $JAVA_HOME/lib/security/cacerts
for DOMAIN in $DOMAINS_TO_WHITELIST_FOR_SSL_SPACE_SEPARATED; do
echo "echo -n | openssl s_client -connect $DOMAIN:443 | openssl x509 | keytool -storepass changeit -noprompt -trustcacerts -alias $DOMAIN -importcert -keystore $JAVA_HOME/lib/security/cacerts"
echo -n | openssl s_client -connect $DOMAIN:443 | openssl x509 | keytool -storepass changeit -noprompt -trustcacerts -alias $DOMAIN -importcert -keystore $JAVA_HOME/lib/security/cacerts

    #       echo -n just gives the server a response so the server doesn't keep waiting on us.
    #       openssl x509 strips out information about the certificate chain and connection details. This is the preferred format to import the certificate into other keystores, apparently.
done
fi

    #   $http_proxy includes http:// and port, gradle proxyHost does not
    #-   no_proxy_with_pipes=${no_proxy//,/\\|}
    # ${no_proxy//,/\\|} is not supported by dash.
    # https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_06_02
    # https://stackoverflow.com/questions/53680485/bin-dash-bad-substitution
    #-   no_proxy_with_pipes=$(echo $no_proxy | sed 's/,/\\|/g')
    # If we put this in JAVA_TOOL_OPTIONS rather than provide it on the command line, then \| retains the backslash, making it nonfunctional.
no_proxy_with_pipes=$(echo $no_proxy | sed 's/,/|/g')

    #-   no_proxy_with_pipes_and_stars=${no_proxy_with_pipes//|./|*.}
no_proxy_with_pipes_and_stars=$(echo "$no_proxy_with_pipes" | sed 's/|\./|*./g')
JAVA_TOOL_OPTIONS="-Dhttp.proxyUser=user -Dhttp.proxyPassword=nopass -Dhttp.proxyHost=$proxy_host -Dhttp.proxyPort=$proxy_port -Dhttp.nonProxyHosts='$no_proxy_with_pipes_and_stars' -Dhttps.proxyUser=user -Dhttps.proxyPassword=nopass -Dhttps.proxyHost=$proxy_host -Dhttps.proxyPort=$proxy_port -Dhttps.nonProxyHosts='$no_proxy_with_pipes_and_stars'"
if ls $JAVA_HOME/lib/security/cacerts; then
JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -Djavax.net.ssl.trustStore=$JAVA_HOME/lib/security/cacerts"
fi

    #   We should have a way to specify a different trust store password if necessary.
JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -Djavax.net.ssl.trustStorePassword=changeit"
echo "JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS"
export JAVA_TOOL_OPTIONS
fi
if command -v gradle; then
GRADLE_OPTS="$JAVA_TOOL_OPTIONS -Dorg.gradle.internal.http.socketTimeout=120000 -Dorg.gradle.internal.http.connectionTimeout=120000"
echo "GRADLE_OPTS=$GRADLE_OPTS"
fi


right_before_install_nss=$(date +%s)
if [ -d $HOME/.pki/nssdb ]; then ls -l $HOME/.pki/nssdb/; else
echo "$HOME/.pki/nssdb not found; looking to create it."
if command -v apk && [ $(id -u) -eq 0 ]; then
if [ -d pki/nssdb/ ]; then
echo "Found pki/nssdb/ so copying that."
else
echo "No NSS DB found, but $PROXY_CA_PEM found, so creating an NSS DB."
apk add nss-tools || (sed -i -e 's/https/http/' /etc/apk/repositories && apk add nss-tools)
mkdir --parents pki/nssdb/

    # create https://www.dogtagpki.org/wiki/NSS_Database#Creating_Database
    # - certutil --help crashes?
certutil -N -d pki/nssdb/ --empty-password

    # $HOME/.pki/nssdb seems to be where Chromium looks, at least
    # - certutil -d  -A -t "P,," -n proxycert -i $PROXY_CA_PEM does not seem to matter, the C version is required for chromium at least
certutil -d sql:pki/nssdb/ -A -t "C,," -n proxycertasCA -i $PROXY_CA_PEM

    # Ideally we wouldn't apk del this if it was already installed, but apk doesn't seem to provide a way to check that.
    # apk del nss-tools doesn't apk del nss, so this probably isn't a big deal.
apk del nss-tools
fi
ls -l pki/nssdb/
mkdir --parents $HOME/.pki/nssdb/

    # Chromium chokes if we symbolic-link the directory
    # ERROR:nss_util.cc(53) Failed to create /root/.pki/nssdb directory.
    # https://chromium.googlesource.com/chromium/src/+/refs/heads/master/crypto/nss_util.cc#46
    # Chromium also chokes if we symbolic-link each individual file
    # - ln -s pki/nssdb/cert9.db $HOME/.pki/nssdb/
    # - ln -s pki/nssdb/key4.db $HOME/.pki/nssdb/
    # - ln -s pki/nssdb/pkcs11.txt $HOME/.pki/nssdb/
    # ERROR nss_util.cc(166) Error initializing NSS with a persistent database (sql:/root/.pki/nssdb) NSS error code -8174
    # So we just copy the entire directory.
cp -r pki/nssdb/ $HOME/.pki/
echo $HOME/.pki/nssdb
ls -l $HOME/.pki/nssdb
fi
fi
echo "adding cert to nss db took $(( $(date +%s) - right_before_install_nss)) seconds"



    # Old Docker images have Python 2; we treat that as not having Python.
    # As perverse as it may be, some images have python3 but do not have pip.
command -v $PYTHON_TO_USE && $PYTHON_TO_USE -c "import sys; print(sys.version_info.major)"
if command -v $PYTHON_TO_USE && [ $($PYTHON_TO_USE -c "import sys; print(sys.version_info.major)") -ge 3 ] && $PYTHON_TO_USE -m pip; then

    # If some of the links in your documentation require a special PEM to verify,
    # then sphinx -b linkcheck will fail without that PEM.
    # But setting REQUESTS_CA_BUNDLE to that PEM will cause other links to fail,
    # because the runner will only accept that PEM, not the defaults.
    # Therefore you will usually want to bundle all certificates together with
$PYTHON_TO_USE --version
$PYTHON_TO_USE -m pip --version || echo "The executable called $PYTHON_TO_USE does not have pip."
$PYTHON_TO_USE -c "import setuptools; print(setuptools.__version__)"

    # cat `python -c "import requests; print(requests.certs.where())"` ~/your.pem > ~/bundled.pem
    # pip uses requests, but not the normal requests.
    # pip uses a vendored version of requests, so that pip will still work if anything goes wrong with your requests installation.
    # We find where that vendored version of requests keeps its certs and merge in the cert from PROXY_CA_PEM.
    # On some systems, we might need to try the import twice, and the first time, it will fail with an AttributeError.
    # Therefore we need a block to suppress the AttributeError, which requires a colon.
    # But that causes parsing of .gitlab-ci.yml to fail with "before_script config should be an array of strings",
    # so we need to wrap the entire line in ''.
    # https://gitlab.com/gitlab-org/gitlab-foss/merge_requests/5481
    # - 'echo -e "import contextlib\nwith contextlib.suppress(AttributeError): import pip._vendor.requests\nfrom pip._vendor.requests.certs import where\nprint(where())" | python'
    # - 'cat `echo -e "import contextlib\nwith contextlib.suppress(AttributeError): import pip._vendor.requests\nfrom pip._vendor.requests.certs import where\nprint(where())" | python` $PROXY_CA_PEM > bundled.pem'
    # Unfortunately, echo -e is not supported on all platforms (onthe official TensorFlow image, in particular),
    # resulting in a mysterious SyntaxError on "-e import contextlib".
    # Thus, we cannot use linebreaks.
    # Still, for the sake of transparency we don't want to call out to an opaque script.
    # We can operate the context manager manually.
    # .suppress is not available in Python 2, so if python points at Python 2, we want to be sure to actually invoke Python 3.
$PYTHON_TO_USE -c "import contextlib; contextManager = contextlib.suppress(AttributeError); contextManager.__enter__(); import pip._vendor.requests; contextManager.__exit__(None,None,None); from pip._vendor.requests.certs import where; print(where())"
cat $($PYTHON_TO_USE -c "import contextlib; contextManager = contextlib.suppress(AttributeError); contextManager.__enter__(); import pip._vendor.requests; contextManager.__exit__(None,None,None); from pip._vendor.requests.certs import where; print(where())") ${PROXY_CA_PEM} > bundled.pem
ls bundled.pem

    # In the unlikely event that the image does not have Python available, the above command may silently fail to write bundled.pem.
    # Thus we check python --version above and double-check that bundled.pem exists with ls.
    # pwd might end in a / on some systems
    # We need to add a / if and only if pwd does not already end in a /.
export REQUESTS_CA_BUNDLE="${PWD%/}/bundled.pem"
export GIT_SSL_CAINFO="${PWD%/}/bundled.pem"

    # - SSL_CERT_FILE="${PWD}/bundled.pem" does not seem to be used by programs
    # We include the working directory PWD so that REQUESTS_CA_BUNDLE can still be found from another directory.
    # This seems to matter when activating and using a conda environment, for some reason.
echo "REQUESTS_CA_BUNDLE found at $(ls $REQUESTS_CA_BUNDLE)"
echo "Merging the certificate bundle took $(( $(date +%s) - right_before_pull_cert)) seconds total"

    # REQUESTS_CA_BUNDLE works for *almost* everything, including install_requires, but not setup_requires.
$PYTHON_TO_USE -m pip config set install.cert $PROXY_CA_PEM || echo "Your default pip is so old that it does not have pip config. You may still be able to create a virtual environment with a more up-to-date pip."
PIP_CERT=$PROXY_CA_PEM
ls $PIP_CERT
fi
# endif python3

fi
# endif PROXY_CA_PEM is set

    # If you set PYPI_URL, the default behavior is to look first in that index, and second in the default pypi.org.
    # pip does not provide a native option to do this, exactly, but we can hack it together by specifying --extra-index-url https://pypi.org/simple.
    # Note however that if pip finds a higher version number in https://pypi.org, pip will use that.
    # We cannot stop pip from doing that, short of telling pip not to check pypi.org at all (in which case your server would have to be a true PyPI mirror).
    # But so long as PYPI_URL contains a version number greater than or equal to the version number on pypi.org, PYPI_URL will be used.
    # The assumed use-case here is package(s) for which open-source publication chronically lags behind internal publication.
    # When the internal version is ahead, all packages using this template (and with PYPI_URL set) will use the latest version.
    # If it doesn't have internal changes, great! pip will just use the pypi.org version.
if [ -z "${PYPI_URL+ABC}" ]; then echo "PYPI_URL is unset."; else
echo "PYPI_URL is set to $PYPI_URL"

    # - "if [ ${PYPI_URL: -1} != '/' ]; then"
    # If the last character of PYPI_URL is not a /
    # If you cut a trailing / and find that you cut nothing
    # https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
    # {parameter%[word]}
    # Remove Smallest Suffix Pattern. The word shall be expanded to produce a pattern. The parameter expansion shall then result in parameter, with the smallest portion of the suffix matched by the pattern deleted. If present, word shall not begin with an unquoted '%'.
if [ "${PYPI_URL%/}" = "${PYPI_URL}" ]; then
echo "PYPI_URL has no trailing /. If you try to twine upload without the trailing /, you'll get back an HTTPError 400 Bad Request Repository path must have another '/' after initial '/'."
fi

    # To ensure a trailing /, we cut a trailing / if there is one and then add a trailing /.
PYPI_URL=${PYPI_URL%/}/

    # https://pip.pypa.io/en/stable/user_guide/#environment-variables
PIP_INDEX_URL="${PYPI_URL}simple"
echo "PIP_INDEX_URL is set to $PIP_INDEX_URL"

    # PIP_INDEX_URL will be ignored by python -m pip if we don't export it.
export PIP_INDEX_URL
PIP_EXTRA_INDEX_URL='https://pypi.org/simple https://alpine-wheels.github.io/index'
echo "PIP_EXTRA_INDEX_URL is set to $PIP_EXTRA_INDEX_URL"

    # PIP_EXTRA_INDEX_URL will be ignored by python -m pip if we don't export it.
export PIP_EXTRA_INDEX_URL
fi
# endif PYPI_URL is set

    ##
    ## With all our proxy variables and certificates in place, we should now be
    ## able to install from repositores, and optionally push to repositories.
    ## Optionally, if you will be making any git commits, set the user name and
    ## email.
    ##

    # With --sitepackages, we can save time by installing once
    # for both regular tests and documentation checks.
    # Building the documentation also requires the package to be importable,
    # if using autodoc and its descendants.
    # Note that the installation will be repeated, once for each job.
    # The installation still will not be shared across jobs.
    # This is not ideal, but if installation takes a very long time, then you
    # might want to use a Docker image with most of your dependencies already
    # installed.

if command -v conda; then
echo "stat -c '%u' $(which conda); id -u"
stat -c '%u' $(which conda)
id -u
if [ $(stat -c '%u' $(which conda)) -eq $(id -u) ]; then

    # conda update --yes --name base --channel defaults conda fails on the official ContinuumIO/anaconda3 Docker image. Yes, really.
    # To make matters worse, when conda fails, it fails *super aggressively* and insists on exiting out of the entire script even if it's being used as the conditional in an if.
    # - conda update --yes --name base --channel defaults conda || echo "conda update --yes --name base --channel defaults conda fails on the official ContinuumIO/anaconda3 Docker image. Yes, really."
    # - if conda list conda-build --name base; then conda update --name base conda-build; fi
if conda list --name base | grep conda-build; then
conda update --yes --name base conda-build
else echo "We did not see conda-build in conda list. You would think we could simply try conda list conda-build since that's what it's for, but strangely, on some systems conda list conda-build kills the whole script when conda-build is not installed, even though it's a condition in an if."
fi
# endif conda list --name base | grep conda-build
else
echo "This user does not own $(which conda), so we cannot update the conda base environment."
fi
# endif user owns conda
fi
# endif command -v conda

if grep 'docker\|lxc' /proc/1/cgroup; then
echo "We are running inside a container, but it might not be a container we control."
fi
if [ -z ${GITLAB_CI+ABC} ]; then
echo "This script is running outside of a GitLab-Runner (no GITLAB_CI), so we will not create a virtual environment now."
else
if ! [ -z ${CI_DISPOSABLE_ENVIRONMENT} ]; then
echo "We are running in a disposable environment, so there is no need to create a virtual environment."
else
if ! echo $CI_RUNNER_TAGS | grep shell; then
echo "Please tag your GitLab-Runner with its executor. Assuming this is a shell executor."
else
# CI_RUNNER_TAGS contains shell
if [ -z ${CI_SHARED_ENVIRONMENT} ]; then false; fi
fi
echo "We are running in a shell executor, so we need to create a virtual environment."
NAME_FOR_PYTHON_TEST_ENV="$CI_RUNNER_ID-$CI_CONCURRENT_ID-test-env"
if command -v conda && ls conda-requirements.txt; then

    # We want it to be the same name each time, because the job might crash in the middle and we want the env to be cleaned up so these envs don't proliferate.
    # But if two runners share a filesystem and a conda install, then if they have the same env name, one will delete the env the other is using.
if [ "$CONDA_DEFAULT_ENV" = "$NAME_FOR_PYTHON_TEST_ENV" ]; then
conda deactivate
fi
if conda env list | grep $NAME_FOR_PYTHON_TEST_ENV; then
conda env remove --yes --name $NAME_FOR_PYTHON_TEST_ENV
fi
conda create --yes --prefix $PWD/$NAME_FOR_PYTHON_TEST_ENV --channel conda-forge --file=conda-requirements.txt

    # conda activate fails without prior configuration of the shell.
source activate $PWD/$NAME_FOR_PYTHON_TEST_ENV
else
if command -v $PYTHON_TO_USE && [ $($PYTHON_TO_USE -c "import sys; print(sys.version_info.major)") -ge 3 ] && $PYTHON_TO_USE -m venv --help; then
if ls $NAME_FOR_PYTHON_TEST_ENV; then
rm -r $NAME_FOR_PYTHON_TEST_ENV
fi
$PYTHON_TO_USE -m venv $NAME_FOR_PYTHON_TEST_ENV --symlinks
source $NAME_FOR_PYTHON_TEST_ENV/bin/activate
fi
# endif venv
fi
# endif conda-requirements.txt
if (command -v conda && ls conda-requirements.txt) || (command -v $PYTHON_TO_USE && [ $($PYTHON_TO_USE -c "import sys; print(sys.version_info.major)") -ge 3 ] && $PYTHON_TO_USE -m venv --help); then
python --version
python -m pip install --upgrade pip setuptools wheel
python -m pip --version || echo "The executable called $PYTHON_TO_USE does not have pip."
python -c "import setuptools; print(setuptools.__version__)"
fi
# endif either conda env or venv
fi
# endif echo $CI_RUNNER_TAGS | grep docker
fi
# endif running outside runner

    # If the docs include a Jupyter notebook, we need ipykernel to build the docs (including running doctests).
    # Without ipykernel, attempting to --execute Jupyter notebooks when building the documentation will fail with
    # No such kernel named python3
if command -v jupyter && (ls *.ipynb || ls docs/*.ipynb); then
$PYTHON_TO_USE -m pip install ipykernel
$PYTHON_TO_USE -m ipykernel install || echo "Failed to install the default python3 to ipykernel. You might still be able to ipykernel install your preferred env."

    # - pip install ipywidgets # without this, module 'plotly.graph_objects' has no attribute 'FigureWidget'
    # But we don't always need ipywidgets, have separate logic just for Jupyter
fi


    # If the documentation requires the package installed, then
    # set a variable on the derived job.
if [ -z ${DOCS_REQUIRE_PACKAGE+ABC} ]; then
echo "DOCS_REQUIRE_PACKAGE is not set, so we will leave it to the test job to install the package."
else
if command -v $PYTHON_TO_USE && [ $($PYTHON_TO_USE -c "import sys; print(sys.version_info.major)") -ge 3 ] && ls setup.py; then
$PYTHON_TO_USE -m pip install --upgrade pip

    # We install the package separately so that we can continuously monitor how long installation takes.
right_before_pip_install=$(date +%s)
$PYTHON_TO_USE -m pip install .
echo "Installing your package took $(( $(date +%s) - right_before_pip_install)) seconds total"
fi
# if command -v python
fi
# if DOCS_REQUIRE_PACKAGE
if command -v tox; then

    # The old setuptools handled setup_requires with easy_install, which did not have any analogue to REQUESTS_CA_BUNDLE.
    # tox, even tox --sitepackages, would fail with an SSL certificate error if you had anything in setup_requires.
    # https://github.com/pypa/setuptools/issues/1630
$PYTHON_TO_USE -m pip install --upgrade setuptools
fi


echo "before_script took $(( $(date +%s) - right_after_pull_docker_image)) seconds total"


# https://docs.gitlab.com/ee/ci/yaml/yaml_optimization.html#reference-tags
# You can't reuse a section that already includes a !reference tag. Only one level of nesting is supported.

