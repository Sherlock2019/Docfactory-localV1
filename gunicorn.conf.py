# gunicorn.conf.py

import multiprocessing

# Bind to host/port
bind = "0.0.0.0:8000"

# How many worker processes?
workers = multiprocessing.cpu_count() * 2 + 1

# Worker class ('sync' is fine for CPU-light web apps)
worker_class = "sync"

# Graceful timeout (seconds)
timeout = 30

# Max requests per worker before restart (to mitigate memory leaks)
max_requests = 1000
max_requests_jitter = 50

# Logging
accesslog = "-"     # send access logs to stdout
errorlog  = "-"     # send error logs to stderr
loglevel  = "info"
