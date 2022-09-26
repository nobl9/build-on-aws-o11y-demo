import math
from locust import HttpUser, task, between
from locust import LoadTestShape

class StandardUser(HttpUser):
    wait_time = between(0.5,2)

    @task(5)
    def good(self):
        self.client.get("/good")

    @task(2)
    def ok(self):
        self.client.get("/ok")

    @task(3)
    def bad(self):
        self.client.get("/bad")

    @task(4)
    def acceptable(self):
        self.client.get("/acceptable")

    @task(2)
    def veryslow(self):
        self.client.get("/veryslow")

    @task(3)
    def unpredictable(self):
        self.client.get("/err")

    @task(2)
    def not_found(self):
        self.client.get("/notfound")

class DoubleWave(LoadTestShape):
    """
    A shape to imitate some specific user behavior. In this example, midday
    and evening meal times. First peak of users appear at time_limit/3 and
    second peak appears at 2*time_limit/3
    Settings:
        min_users -- minimum users
        peak_one_users -- users in first peak
        peak_two_users -- users in second peak
        time_limit -- total length of test
    """

    min_users = 500
    peak_one_users = 2000
    peak_two_users = 1000
    time_limit = 600

    def tick(self):
        run_time = round(self.get_run_time())

        if run_time < self.time_limit:
            user_count = (
                (self.peak_one_users - self.min_users)
                * math.e ** -(((run_time / (self.time_limit / 10 * 2 / 3)) - 5) ** 2)
                + (self.peak_two_users - self.min_users)
                * math.e ** -(((run_time / (self.time_limit / 10 * 2 / 3)) - 10) ** 2)
                + self.min_users
            )
            return (round(user_count), round(user_count))
        else:
            return None
