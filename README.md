# Overview

These instructions will assist you in creating a publicly accessible
TOM. After following these instructions, you should have a TOM
listening at the URL of your choice.

# Concepts

An operational TOM is composed of several cooperating components, and
within this repository, each runs in its own Kubernetes pod:

- Application: your Django TOM served by a production WSGI server
  (e.g., gunicorn), exposed via a Kubernetes Service
- Database: PostgreSQL managed by CloudNativePG (CNPG)
- Ingress Controller: NGINX that accepts public HTTP(S) and routes it
  to your app’s Service
- cert-manager: obtains and renews TLS certificates (e.g., Let’s Encrypt)

We deploy these components to Kubernetes.

From a high level, Kubernetes orchestrates databases, web servers, and
other services. Orchestration here means automated lifecycle
management: scheduling/restarting pods, applying configuration,
exposing Services, wiring Ingress to Services, and attaching
persistent storage from declarative manifests.

These programs are defined in containers, which, when they are running
in Kubernetes, are called pods. Pods can be annotated so that
Kubernetes knows which of them run on ports. Kubernetes uses Docker, a
lightweight framework for containerized processes, which allows it to
treat relatively small pieces of code as independent machines with
independent operating systems, complete with all of the dependencies
they need and the ability to communicate with each other like physical
machines.

This flexiblity allows for a good deal of control over the environment
of the processes deployed to Kubernetes clusters. It is easy to "turn
it off and on," which helps make deployments reproducible. Kubernetes
and Docker, similar to Java, seem to want to allow their users to
"write once and run anywhere," and while they do not succeed, they
eliminate some of the complexity of worrying about the underlying
system's package versions, networking architecture, and other details.

Kubernetes and Docker are, in turn, implemented on lower‑level
platforms (cloud providers or on‑prem). Kubernetes abstracts many
provider differences to reduce migration friction.

                                                +---------+    +-------------+    +----------------+
                    +------+     +---------+  /-+ service +----+ TOM backend +--+-+ object storage |
                    | user +-----+ ingress +--  +---------+    +-------------+  | +----------------+
                    +------+     +---------+                                    |
																			    |
                                                                                | +----------+
    Deployment                                                                  +-+ Postgres |
                                                                                  +----------+



                                             +---------------------+
    Orchestration                            | Kubernetes / Docker |
                                             +---------------------+



                        +-------------------------+ +-----------------+ +---------------------+ +---------------+
    Platform            | Google Compute Platform | | Microsoft Azure | | Amazon Web Servcies | | Local Cluster |
                        +-------------------------+ +-----------------+ +---------------------+ +---------------+

Helm is a relatively thin layer on top of Kubernetes that packages and
configures deployments. In this setup, Helm creates the Ingress,
Services, Deployments (your gunicorn app), and the CNPG Cluster
(Postgres).

Further reading:
- Kubernetes: https://kubernetes.io/docs/home/
- Helm: https://helm.sh/docs/intro/using_helm/
- Ingress‑NGINX: https://kubernetes.github.io/ingress-nginx/
- cert‑manager: https://cert-manager.io/docs/
- CloudNativePG: https://cloudnative-pg.io/documentation/

# Prerequisites

You should have a working TOM.

The instructions below will set you up with the following additional
requirements, if you do not already have them:

- a DNS provider, which can be Squarespace or the provider of your
  choice, and
- a cloud provider of your choice, which can be EKS (Amazon Elastic
  Kubernetes Service) or GKE (Google Kubernetes Engine).

# Setup

## Squarespace for DNS

### What DNS Is and Why You Need It

DNS (Domain Name System) maps human‑readable names to IP addresses. You
need a DNS record (usually an A record) pointing your TOM’s hostname to
the static IP address of your Ingress.

### Squarespace Setup

If you have the ability to create DNS A records, don't worry about
this step. Furthermore, alternatives to Squarespace exist, and it will
be much easier to follow these instructions with an alternative DNS
provider than an alternative cloud provider.

But, if you need a domain, visit https://domains.squarespace.com, or
Google for "squarespace domains." Then search for a domain you'd like
to use; evaluate the terms, conditions, and price; and, if you'd like,
buy it!

## Cloud Provider Option 1: Amazon Elastic Kubernetes Service (EKS)

One option for a cloud provider is EKS, which is a cloud service
hosted by Amazon. To follow along using EKS, you will need an Amazon
Web Services (AWS) account. AWS provides the machines (nodes) that
comprise a cluster on which Docker containers will be run within
Kubernetes.

If you would prefer to use GKE you can skip to the section on
[GKE](#cloud-provider-option-2-google-kubernetes-engine-gke) below.

The instructions below for setting up EKS generally follow Amazon's
instructions here:
- https://docs.aws.amazon.com/eks/latest/userguide/setting-up.html

### Account and Billing Setup

To set up an account with AWS, navigate to https://aws.amazon.com/ and
create an account. You will need to set up a billing account.

### AWS Commandline Tool Installation

You can follow the instructions
[here](https://docs.aws.amazon.com/eks/latest/userguide/install-awscli.html)
to
[install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
and configure the AWS commandline (CLI) tool.

Note that [the
instructions]((https://docs.aws.amazon.com/eks/latest/userguide/install-awscli.html))
allow for configuring either a single-user or multi-user site. In the
case of a single-user site, the command-line tool will operate with
the permissions of your root user, and Amazon will warn you when you
create the credentials for that user that this is not
recommended. Even so, the author chose this method for
simplicity.

If you would prefer to configure a separate IAM user for use in
spinning up your EKS cluster, you will need to configure that user
with all of the permissions necessary to do so. (And for the new user
to be valuable from a security perspective, it should presumably not
have additional permissions.) Doing so is beyond the scope of these
instructions (and the author did not find instructions for doing so in
the documentation for [setting up
EKS](https://docs.aws.amazon.com/eks/latest/userguide/setting-up.html),
but if you have done so, you can use the credentials created for that
user in the instructions below.

The credentials you have created using the instructions above should
come in the form of a CSV with two columns: "Access key ID," and
"Secret access key." Following the instructions, type

    aws configure

and paste the data from the CSV into the appropriate fields. Select
the region you want from the list
[here](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html). You
may choose to simply use the zone closest to you unless you need a
feature you need in another region, or unless the features you need
are priced differently. Testing for this guide was done in the
`us-west-1` region.

### Installing eksctl

Install eksctl using the instructions
[here](https://docs.aws.amazon.com/eks/latest/eksctl/installation.html). This
tool provides a ssimplified interface, compared to the AWS cli, for
managing Kubernetes clusters, but you will still need the AWS cli tool
for some steps.

### Launch Your Cluster

After following these instructions to set up EKS, you can skip to the
[Configuration](#Configuration) section below. GKE is not needed if
you use AWS.

## Cloud Provider Option 2: Google Kubernetes Engine (GKE)

Another option for a cloud provider is GKE, which is a cloud service
provided by Google. To follow along using GKE, you will need a Google
Cloud account. Google Compute Platform (GCP) provides the hosting
(nodes that run your pods), storage (Persistent Disks for Postgres,
Artifact Registry for images), and networking (load balancers and
public IPs) used here.  macOS users can install the SDK with the PKG
installer. In addition to the capabilities used here, GCP provides
many other tools. These tools generally allow users to run various
kinds of programs on computers in GCP's data center, and to make these
computers accessible to themselves or the public.

### Account and Billing Setup

Once you've decided you would like to create a Google Compute Platform
account, navigate to https://cloud.google.com, or search for Google
Compute Platform. If the terms and conditions are acceptable to you,
create your account.

After you've created an account, set up billing. When the author
created an account in September 2025, billing could be started by
clicking on a button that said "Try for free." Setting billing up
still required a credit card.

In the dropdown boxes, Google asked the following questions, an the
author answered them as follows:

* Question: How would you like to get started today? Answer: Build
  production-ready solutions.
* Question: What do you want to do with Google Cloud first? Answer:
  Build or deploy web or mobile applications.
* Question: What are you trying to do with apps or websitse? Answer: I
  want to host a website.

The author is not sure what, if anything, would have been different if
the questions had been answered differently.

### Gcloud Commandline Tool Installation

Next, install the [gcloud commandline
tool](https://cloud.google.com/sdk/docs/install).  There are multiple
options available. The author chose to click on the targball for his
system, gcloud-cloud-cli-linux-x86_64.tar.gz, and untar it and
install:

    tar zxf google-cloud-cli-linux-x86_64.tar.gz
    bash ./google-cloud-sdk/install.sh

Ensure that the tarball you choose is correct for your platform. After
that, you should have access to the `gcloud` command.

### Gcloud Commandline Tool Authorization

In order to use the `gcloud` command to control Google Cloud
resources, you'll need to authenticate. This opens a browser
tab. Follow the prompts, and after you log in on the browser, you will
be logged into gcloud.

    gcloud auth login

# Configuration

The header of `common_config.sh` lists required variables; more context
is provided further down.

## Updating an Existing TOM

Before you deploy your TOM to the cloud, you will need to ensure that
it meets the minimum requirements laid out in this subsection. 

1. Make sure this repository is inside the directory for your TOM.
2. For the docker container to build properly and push to your
   environment, the following should be added to a requrements.txt
   file at the base of your TOM, if any of these are not already
   present there, with the exceptions noted in the comments below:
   tomtoolkit
   django-storages[google] # only needed for GKE
   google-cloud-storage    # only needed for GKE
   django-storages[s3]     # only needed for EKS
   gunicorn
   gevent
   greenlet
   psycopg2-binary
   whitenoise
3. If you don't already have one, copy templates/local\_settings.py
   from this directory into the root directory of your TOM. If you do
   have such a local\_settings.py, you will need to merge the one in
   this repository with yours.
4. At the end of your settings.py, add the following:
   update_settings(globals())

# Install Utilities

## jq

The jq program is an extremely useful utility for manipulating
JSON-serialized information. The commandline tools you will be using
to deploy the TOM use jq extensively, and this tool will likely come
in handy. It is also required by the deployment scripts above.

## Kubectl

Install kubectl to interact with your Kubernetes cluster:
- https://kubernetes.io/docs/tasks/tools/

## Helm

Install Helm onto your machine to install Helm charts on top of
Kubernetes:
- https://helm.sh/docs/intro/install/

# Create the Administrative Account

Create the administrative account. `kubectl` transparently manages
authentication for you. This command runs `manage.py createsuperuser`
inside the app pod to create a Django superuser. After this, use the
web UI to sign in with the new account.

	. scripts/common_config.sh
    kubectl -n "$kubernetes_namespace" exec -it "deploy/tom-${tom_name_lowercase}" -- python manage.py createsuperuser

You only need to perform this action once after the server is running.

# Run the Scripts

First, set the name of your TOM. This should be the same as the one
you've created with make-tom.sh. This is required by both scripts run
below.

    export tom_name=YOUR_TOM_NAME_HERE
    export tom_hostname=YOUR_SITE_HOSTNAME_HERE

- The tom\_name should match the name of your TOM as you originally
  created it.
- The YOUR\_SITE\_HOSTNAME\_HERE should be the fully-qualified domain
  name that you eventually want to point to your TOM. If you don't
  have this yet, you can set it to what you would eventually like it
  to be, or even to a test domain, but it will not be possible for
  others to easily access your site due to security restrictions on
  clients not accessing the site through the proper fully-qualified
  domain name.

The orchestration scripts, which reside in the scripts directory of
this repository, can be run standalone, but they also include comments
that help understand the process of deploying to the Google Compute
Platform and running Kubernetes on top of that.

After everything above has been run and configured, it should be
possible to simply run the scripts. First, create the Kubernetes
cluster inside Google Compute Engine. This is a blank slate on which
Kubernetes can deploy its objects:

    bash scripts/create_kubernetes_cluster_gcp.sh

It is possible that something in that script will fail due to changes
in the Google Compute Platform API, differences in your environment,
changed configuration, or other issues. If it fails, look at the
comments near the commandline that failed. If you are able to resolve
the issue, you should be able to simply rerun the script, which will
pick up where it left off. If the error messages you see are related
to timeouts, for example, it may make sense to simply try rerunning
the script once.

If you are running on GKE at this point, this is probably a good time
to ensure that you have credentials to manipulate your GCP environment
from the commandline:

    gcloud auth application-default login

Once that is complete, deploy the Kubernetes cluster:

    export certmanager_email=YOUR_EMAIL_HERE 
    bash scripts/launch_kubernetes.sh

Similarly, it should be possible to continuously rerun the script
while fixing any issues that arise while running it.

# Connecting to Your Instance

## Retrieving Your Static IP

After your cluster has started, you can use the following command to
retrieve the static IP address assigned to your django server

    . scripts/common_config.sh ; kubectl -n "$kubernetes_namespace" get ingress 

- If you are running on GKE, the IP address will be in the ADDRESS
  column.
- If you are running on EKS, the hostname of the load balancer will be
  in the ADDRESS column. You can run 
    host LOAD\_BALANCER\_HOSTNAME\_HERE
  which will resolve to one or more static IP addresses.

## Configuring DNS

The following instructions set up an A record pointing your hostname
to the static IP or IPs you found above. In EKS, you may have more
than one IP. In that case, simply repeat the instructions below for
both IPs, using the *same hostname*. Clients will then choose which
static IP to connect to, both of which are valid ways to connect to
your instance.

In Squarespace, or in the DNS tool of your choice, create a DNS A record
that maps your domain name to the address above.

If you are using Squarespace, log in, navigate to your account's
domains, click on the domain you want to use, and click "DNS." There
you should be presented with DNS settings. There is a section for
"Custom Records" at the bottom, and there is a button that says "ADD
RECORD." Click that button.

- There is an text box for HOST. If your domain is foo.com and you
  want to create a DNS entry for bar.foo.com, just enter "bar"
  here. You don't need the fully qualified name, at least not for
  Squarespace.
- In the "TYPE" selector, choose "A".
- In the "TTL" selector, choose 4 hours.
- In the "DATA" text box, enter the IP address.

The TTL selection will control how long the record is cached. If you
change the IP address for this record, various caches between you and
the main DNS server, including caches on your computer, may store the
record for this long.

## Connecting to Your Instance

The next step in the process is ensuring that Transport Layer Security
(TLS) is configured for the site and that you can connect to your
instance. TLS is the protocol behind HTTPS (HTTP Secure); it encrypts
browser/server traffic and authenticates your site with a
certificate. TLS certificates can in turn be signed by a certificate
authority trusted by users' web browsers. Trusted certificate
authorities' certificates are distributed with popular operating
systems and browsers, which allows users to know that they are
connecting securely to your site.

In order to get a certificate signed by a trusted root certificate
authority, you generally need to create a certificate signing request
and send that, along with proof of your identity, to a certificate
authority. This deployment script uses a tool called [Let's Encrypt](https://letsencrypt.org) 
to automatically prove ownership over a domain name, and to retrieve a
signed TLS certificate in this way.

It may take a moment for your instance to work. When you navigate to
the site, you should initially see a privacy warning. Clicking through
to retrieve information about the certificate, you should see that the
name of the certificate authority has (STAGING) in its name. That's
because the Let's Encrypt certificate we are using by default points
to the staging environment. To change that, edit
[common_config.sh](scripts/common_config.sh) and edit the
`letsencrypt_env` variable. Change its default to
`prod`. Alternatively, you can export it, but you must remember to do
so each time you run launch_kubernetes.sh

It will take a few minutes for the production TLS certificate to function,
but at this point you should be able to navigate to the hostname you
chose and log in with the administrative username and password you
selected.

## Transferring Data

To transfer data from an existing TOM to the external TOM that you
have just deployed, you can use
[transfer_data.sh](scripts/transfer_data.sh) script.

    export tom_name=YOUR_TOM_NAME_HERE
    . scripts/common_config.sh
    gcloud auth application-default login
	bash scripts/transfer_data.sh

WARNING: The script above will point all of your data on your *local*
TOM to the cloud in preparation for transfer, so use it carefully!
That script will also delete all data on the TOM you've just spun
up.

The script uses Django's builtin `dumpddata` and `loaddata` commands,
which have the adavantage of being fairly portable. But these commands
may not be fast enough for extremely large databases with, say,
hundreds of thousands of entries. If better performance is needed
during migration, [pgloader](https://pgloader.io) may be a good
option.

## Code Modifications

After making modifications to the code or your local TOM, you should
be able to push your changes up to your Kubernetes cluster by
rerunning the launch\_kubernetes.sh command as described above. Note
that this will not push new data from your local TOM to the remote
cluster. Currently, only the transfer\_data.sh script, as described
above, will do that. And it will delete all of the data on your remote
server first.

## Running Cron Jobs

If you would like to create jobs that run on a pod very similar to the
Django server pod, follow the pattern laid out in
[values.yaml](helm-chart/values.yaml). After configuring whatever job
you would like, rerun the launch_kubernetes.sh script as described
above and your jobs will be created. By default, two jobs are created:
one to clear user sessions at 3 AM and another small test job that
runs every 5 minutes.

# Troubleshooting

With the exception fo the transfer_data script, the scripts above are
designed to be run over and over. Successive runs should push the
system toward a good state and preserve that good state, whether or
not the script fails. 

If you encounter a problem when running the scripts, look at the last
command that was run by the script before you had the issue. The
commands will be prefaced with a +, like this:

    + docker build --platform linux/amd64 --build-arg TOM_NAME=TOMNAME5 -t us-central1-docker.pkg.dev/tom-tomname5-project/tom-repo/tom-tomname5-image:tom-tomname5-865aad967d1f .


The last line in the file with a + before it will almost always be the
command that failed. Lines that begin with |, on the other hand, are
informational. The best way to try to debug an error is to look at the
informational messages that occur just before the command that failed.

