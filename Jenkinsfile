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
    'alma8': {
      node {
        sh 'setup_centreon_build.sh'
        sh './centreon-build/jobs/vmware/vmware-package.sh alma8'
        archiveArtifacts artifacts: 'rpms-alma8.tar.gz'
        stash name: "rpms-alma8", includes: 'output/noarch/*.rpm'
        sh 'rm -rf output'
      }
    },
    'Debian bullseye packaging and signing': {
      node {
        dir('centreon-vmware') {
          checkout scm
        }
        sh 'docker run -i --entrypoint "/src/centreon-vmware/ci/scripts/vmware-deb-package.sh" -w "/src" -v "$PWD:/src" -e "DISTRIB=bullseye" -e "VERSION=$VERSION" -e "RELEASE=$RELEASE" registry.centreon.com/centreon-debian11-dependencies:22.04'
        stash name: 'Debian11', includes: '*.deb'
        archiveArtifacts artifacts: "*"
      }
    }
    if ((currentBuild.result ?: 'SUCCESS') != 'SUCCESS') {
      error('Package stage failure.');
    }
  }
  stage('Delivery') {
    node {
      sh 'setup_centreon_build.sh'
      unstash "rpms-centos7"
      unstash "rpms-alma8"
      sh './centreon-build/jobs/vmware/vmware-delivery.sh'
      withCredentials([usernamePassword(credentialsId: 'nexus-credentials', passwordVariable: 'NEXUS_PASSWORD', usernameVariable: 'NEXUS_USERNAME')]) {
        checkout scm
        unstash "Debian11"
        sh '''for i in $(echo *.deb)
              do 
                curl -u $NEXUS_USERNAME:$NEXUS_PASSWORD -H "Content-Type: multipart/form-data" --data-binary "@./$i" https://apt.centreon.com/repository/22.04-unstable/
              done
           '''    
      }     
    }
  }
} catch(e) {
  if (env.BRANCH_NAME == 'master') {
    slackSend channel: "#monitoring-metrology", color: "#F30031", message: "*FAILURE*: `CENTREON VMWARE` <${env.BUILD_URL}|build #${env.BUILD_NUMBER}> on branch ${env.BRANCH_NAME}\n*COMMIT*: <https://github.com/centreon/centreon-vmware/commit/${source.COMMIT}|here> by ${source.COMMITTER}\n*INFO*: ${e}"
  }
}
