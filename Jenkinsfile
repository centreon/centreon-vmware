stage('Source') {
  node {
    sh 'setup_centreon_build.sh'
    dir('centreon-vmware') {
      checkout scm
    }
    sh './centreon-build/jobs/vmware/vmware-source.sh'
    source = readProperties file: 'source.properties'
    env.VERSION = "${source.VERSION}"
    env.RELEASE = "${source.RELEASE}"
    if (env.BRANCH_NAME == 'master') {
      withSonarQubeEnv('SonarQubeDev') {
        sh './centreon-build/jobs/vmware/vmware-analysis.sh'
      }
    }
  }
}

try {
  stage('Package') {
    parallel 'centos7': {
      node {
        sh 'setup_centreon_build.sh'
        sh './centreon-build/jobs/vmware/vmware-package.sh centos7'
        archiveArtifacts artifacts: 'rpms-centos7.tar.gz'
        stash name: "rpms-centos7", includes: 'output/noarch/*.rpm'
        sh 'rm -rf output'
      }
    },
    'centos8': {
      node {
        sh 'setup_centreon_build.sh'
        sh './centreon-build/jobs/vmware/vmware-package.sh centos8'
        archiveArtifacts artifacts: 'rpms-centos8.tar.gz'
        stash name: "rpms-centos8", includes: 'output/noarch/*.rpm'
        sh 'rm -rf output'
      }
    }
    if ((currentBuild.result ?: 'SUCCESS') != 'SUCCESS') {
      error('Package stage failure.');
    }
  }
  stage('Delivery') {
    sh 'setup_centreon_build.sh'
    unstash "rpms-centos7"
    unstash "rpms-centos8"
    sh './centreon-build/jobs/vmware/vmware-delivery.sh'
  }
} catch(e) {
  if (env.BRANCH_NAME == 'master') {
    slackSend channel: "#monitoring-metrology", color: "#F30031", message: "*FAILURE*: `CENTREON VMWARE` <${env.BUILD_URL}|build #${env.BUILD_NUMBER}> on branch ${env.BRANCH_NAME}\n*COMMIT*: <https://github.com/centreon/centreon-vmware/commit/${source.COMMIT}|here> by ${source.COMMITTER}\n*INFO*: ${e}"
  }
}
