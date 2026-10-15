pipeline {
  agent any

  options {
    disableConcurrentBuilds()          // два билда одновременно подрались бы за порт 8080 в тестах
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  environment {
    DOCKERHUB_USER       = 'aibutros'
    MOVIE_IMAGE          = "${DOCKERHUB_USER}/movie-service"
    CAST_IMAGE           = "${DOCKERHUB_USER}/cast-service"
    IMAGE_TAG            = "${env.BRANCH_NAME.replaceAll('/', '-')}-${env.BUILD_NUMBER}"
    COMPOSE_PROJECT_NAME = 'jenkins-test'
  }

  stages {

    stage('Build') {
      steps {
        sh 'docker build -t $MOVIE_IMAGE:$IMAGE_TAG ./movie-service'
        sh 'docker build -t $CAST_IMAGE:$IMAGE_TAG ./cast-service'
      }
    }

    stage('Test') {
      steps {
        sh 'docker compose up -d --build'
        sh '''
          for url in http://localhost:8080/api/v1/movies/docs http://localhost:8080/api/v1/casts/docs; do
            for i in $(seq 1 30); do
              if curl -fsS -o /dev/null "$url"; then echo "OK: $url"; break; fi
              if [ "$i" -eq 30 ]; then echo "FAILED: $url"; docker compose logs; exit 1; fi
              sleep 2
            done
          done
        '''
      }
      post {
        always { sh 'docker compose down -v' }
      }
    }

    stage('Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_TOKEN')]) {
          sh 'echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin'
          sh 'docker push $MOVIE_IMAGE:$IMAGE_TAG'
          sh 'docker push $CAST_IMAGE:$IMAGE_TAG'
        }
      }
      post {
        always { sh 'docker logout || true' }
      }
    }

    stage('Deploy dev') {
      steps { deployTo('dev') }
    }

    stage('Deploy qa') {
      steps { deployTo('qa') }
    }

    stage('Deploy staging') {
      steps { deployTo('staging') }
    }

    stage('Deploy prod') {
      when {
        beforeInput true
        branch 'master'
      }
      options {
        timeout(time: 1, unit: 'HOURS')   // если никто не подтвердит за час — билд прерывается
      }
      input {
        message "Deploy ${IMAGE_TAG} to PRODUCTION?"
        ok 'Deploy'
      }
      steps { deployTo('prod') }
    }
  }

  post {
    always {
      sh 'docker image prune -f || true'   // чтобы диск VM не забился старыми слоями
    }
    success { echo "Pipeline OK: ${IMAGE_TAG}" }
    failure { echo "Pipeline FAILED: ${IMAGE_TAG}" }
  }
}

// Общая функция деплоя: все секреты подставляются только на время вызова скрипта
def deployTo(String envName) {
  withCredentials([
    file(credentialsId: 'kubeconfig',        variable: 'KUBECONFIG'),
    string(credentialsId: 'movie-db-password', variable: 'MOVIE_DB_PASSWORD'),
    string(credentialsId: 'cast-db-password',  variable: 'CAST_DB_PASSWORD')
  ]) {
    sh "bash scripts/deploy.sh ${envName} ${env.IMAGE_TAG}"
  }
}
