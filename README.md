# Redis Sentinel Deployment Template for OpenShift (Origin)

## Overview

This project aims to provide a missing template for creating Redis Sentinel cluster in OpenShift Origin.
The basic idea is to create a standalone **pod** with 1 replica to launch a redis master 
along with a sentinel container in it. 
Then launch a DeploymentConfig (dc) to create and scale multiple redis slaves. 
This dc contains a pod with a redis slave container and redis sentinel container. 

## Prerequisites
Before using the template including in this project, you need to make sure the following prerequisites:

1. OpenShift Origin server v3.6.0 or above available
2. OpenShift cli tool **oc** must be installed in your host machine
3. A private registry or using Docker Hub to maintain your redis sentinel image

> Note: you can get OpenShift via installing MiniShift or download OpenShift Origin server 
from Github into your VM (RHEL or CentOS recommended)*

- [Install Minishift (Recommended)](https://docs.openshift.org/latest/minishift/getting-started/installing.html)
- [OpenShift Advanced Install](https://docs.openshift.org/latest/install_config/install/advanced_install.html)


## Build the docker image and push to registry

> Note: create a [docker hub](https://hub.docker.com/) account if you don't have it yet.

```bash
# Build the image
$ cd openshift-redis-sentinel/dockerimages
$ docker build -t redis-sentinel:latest .
# Tag the image
$ docker tag redis-sentinel <your-doxcker-hub-username>/redis-sentinel
# push to docker hum registry
$ docker login
Login with your Docker ID to push and pull images from Docker Hub. If you don't have a Docker ID, head over to https://hub.docker.com to create one.
Username: <your-doxcker-hub-username>
Password: ****************
Login Succeeded
$ docker push <your-doxcker-hub-username>/redis-sentinel
```

In the `redis-sentinel-template.json` file, adapt the `REDIS_SENTINEL_IMAGE` parameters to reflect
the image you've just pushed. The `value` field should be `<your-doxcker-hub-username>/redis-sentinel`.


```javascript
...
    "parameters": [
        {
            "description": "Redis Sentinel docker image reference",
            "displayName": "Redis Docker Image Ref",
            "name": "REDIS_SENTINEL_IMAGE",
            "required": true,
            "value": "jmetzz/redis-sentinel"
        }
        ...
    ]
...
```

 In this case, once the image
is updated openshift will start a redeploy of your containers based on the template you've configured. 


Ideally you would push the image to a private registry or Docker Hub, but in case you are wondering, 
it is also possible to use the internal openshift docker registry to avoid push images to docker hub.
For this, you have to push the docker image to the openshift (inner) repository and 
adapt the template file.
 
This is how you should proceed:


```bash
# Make sure you are using the docker instance from openshift
$ eval $(minishift docker-env)
# Build the image
$ cd openshift-redis-sentinel/dockerimages
$ docker build -t redis-sentinel:latest .
# Tag the image
$ docker tag redis-sentinel:latest $(minishift openshift registry)/my-project/redis-sentinel:latest
# push to openshift registry
$ oc login -u developer -p dev
$ docker login -u developer -p $(oc whoami -t) $(minishift openshift registry)
$ docker push $(minishift openshift registry)/my-project/redis-sentinel
```

Now adapt the template file:

1. Change the `REDIS_SENTINEL_IMAGE`, removing the `<your-doxcker-hub-username>/` part
2. Change de `lookupPolicy` to `"local" : true` 

> Note: it you've already submited this template once, you need to replace it. Check how on the 
previous sessions.


## Import Template
The OpenShift templates and image streams are often been created and maintained within
**openshift** project, which is one of internal projects by OpenShift itself. 
To import your template you need to login as **system:admin**. 
The sample script would be something as follows:

```bash
$ cd openshift-redis-sentinel
$ oc login -u system:admin
$ oc create -f templates/redis-sentinel-template.json
template.template.openshift.io/redis-sentinel created
$
```

In case you perform any changes on the template, you can also replace it as follows:

```bash
# Make user you've logged in as system:admin, and then
$ oc replace -f templates/redis-sentinel-template.json
```


## Deploy Your App using Template

Deploy Redis Sentinel app into your project
```bash
$ oc login -u developer -p dev -n my-project
Login successful.

You have one project on this server: "my-project"

Using project "my-project".
$ oc process my-project//redis-sentinel | oc create -f -
imagestream.image.openshift.io/redis-sentinel created
pod/redis-master created
deploymentconfig.apps.openshift.io/redis-replicas created
service/redis created
service/redis-sentinel created
service/redis-ingress created
service/redis-reader created
$
```
This should create the objects in your openshift instance.

To test if Redis is working on your setup, make sure you have `redis-cli` installed 
and available on your path. `redis-cli` is the command line interface utility to talk with Redis. 
On Mac OS just use `homebrew` to install it
    
```bash
$ brew install redis
```

Now, get the ingress port to connect to your Redis server, access it and test some commands:

```bash
# Get redis ingress port
$ oc get --export svc redis-ingress
NAME            TYPE           CLUSTER-IP   EXTERNAL-IP     PORT(S)          AGE
redis-ingress   LoadBalancer   <none>       172.29.135.60   6379:32569/TCP   <unknown>
# Connect to the redis instance on minishift cluster
$ redis-cli -h $(minishift ip) -p 32569
$ 192.168.64.3:32569> 
# check if the server is actually runnig
$ 192.168.64.3:32569> ping
PONG
# Check the available keys 
$ 192.168.64.3:32569> keys *
$ (empty list or set)
$ 192.168.64.3:32569> set mykey somevalue
OK
$ 192.168.64.3:32569> get mykey
"somevalue"
```


## Testing failover

Upon failure Redis Sentinel will elect a new master. We can verify this behaviour using the following
commands:

```bash
$ redis-cli -p 26379
# Check the ip of the master node
127.0.0.1:26379> INFO
127.0.0.1:26379> SENTINEL failover mymaster
# Check the ip of the NEW master node
127.0.0.1:26379> INFO
```

## The caveat 

The tricky aspect of this setup is that client applications need to be aware of master node changes. 
Remember only master nodes are writeable in Redis.

Therefore, when implementing the client application you need to foresee support for Redis Sentinel, 
which means deploying a companion container holding Redis Sentinel to keep track of the 
master node address. When writing data to Redis, your application should make use of a compatible
framework to sent the request to the correct node. 
A good example of such a framework is [redis-py](https://github.com/andymccurdy/redis-py).

Have a look at a short example on how to use this framework: 
```python
>>> from redis.sentinel import Sentinel
>>> sentinel = Sentinel([('localhost', 26379)], socket_timeout=0.1)
>>> sentinel.discover_master('mymaster')
('127.0.0.1', 6379)
>>> sentinel.discover_slaves('mymaster')
[('127.0.0.1', 6380)]

# You can also create Redis client connections from a Sentinel instance. 
# You can connect to either the master (for write operations) or 
# a slave (for read-only operations).

>>> master = sentinel.master_for('mymaster', socket_timeout=0.1)
>>> slave = sentinel.slave_for('mymaster', socket_timeout=0.1)
>>> master.set('foo', 'bar')
>>> slave.get('foo')
'bar'
```

A list of available client-side frameworks 
that support Redis Sentinel can be found at https://redis.io/clients#python.
  

## Important Notice

When deployment is completed, the Redis Sentinel cluster is actually not fully up and running. 
You need to wait **for a short while** and attempt to login redis via cli by the ingress port 
exposed by service **redis-ingress**.

When the master node is changed your client application might not be able to write to redis if you app
is not prepared to use Sentinel. Have a look at [redis-py](https://github.com/andymccurdy/redis-py)
and [Guidelines for Redis clients with support for Redis Sentinel](https://redis.io/topics/sentinel-clients) 
to learn how to properly setup the client application.
 

## References

This project was forked from [eliu/openshift-redis-sentinel](https://github.com/eliu/openshift-redis-sentinel)
github repository, which was in turn inspired by the following repo or resources. Many thanks to the respected authors.

- [Running Redis Cluster on OpenShift 3.1](https://github.com/shah-zobair/redis-sentinel#running-redis-cluster-on-openshift-31)
- [Kubernetes Examples: Reliable, Scalable Redis on Kubernetes](https://github.com/kubernetes/examples/tree/master/staging/storage/redis)
- [OpenShift Libraries: Redis Template](https://github.com/openshift/library/tree/master/community/redis)
- [Openshift: how to edit scc non-interactively?](https://stackoverflow.com/questions/42310262/openshift-how-to-edit-scc-non-interactively)
- [OpenShift Templates](https://docs.openshift.com/container-platform/3.4/dev_guide/templates.html)
- [Deploy Redis Sentinel Cluster With K8s](https://o-my-chenjian.com/2017/02/06/Deploy-Redis-Sentinel-Cluster-With-K8s/)

Example of application: 
- [High-Availability with Redis Sentinels: Connecting to Redis Master/Slave Sets](https://scalegrid.io/blog/high-availability-with-redis-sentinels-connecting-to-redis-masterslave-sets/)