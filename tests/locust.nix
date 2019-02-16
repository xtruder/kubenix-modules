{ config, k8s, ... }:

with k8s;

{
  require = [./test.nix ../modules/locust.nix ../modules/nginx.nix];

  kubernetes.modules.nginx = {
    configuration.replicas = 10;
  };

  kubernetes.modules.locust = {
    module = "locust";
    configuration = {
      targetHost = "http://nginx:80";
      locustScript = "/locust-tasks/task.py";
      worker.replicas = 10;
      tasks."task.py" = ''
        from locust import HttpLocust, TaskSet, task

        def index(l):
          l.client.get("http://nginx:80/")

        class UserTasks(TaskSet):
          # one can specify tasks like this
          tasks = [index]

          # but it might be convenient to use the @task decorator
          @task
          def page404(self):
            self.client.get("http://nginx:80/does_not_exist")

        class WebsiteUser(HttpLocust):
          """
          Locust user class that does requests to the locust web server running on localhost
          """

          host = "http://nginx:80"
          min_wait = 0
          max_wait = 0
          task_set = UserTasks
      '';
    };
  };
}
