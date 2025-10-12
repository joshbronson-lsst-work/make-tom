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

You should have a working TOM in this directory (created via
`make-tom.sh` or equivalent). This repo deploys an existing Django
project. It does not generate one.

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

## Google Cloud Platform (GCP)

These instructions are tied to GCP. To follow along, you will need a
Google Cloud account. GCP provides the hosting (GKE nodes that run
your pods), storage (Persistent Disks for Postgres, Artifact Registry
for images), and networking (load balancers and public IPs) used here.
macOS users can install the SDK with the PKG installer. In addition to
the capabilities used here, GCP provides many other tools. These tools
generally allow users to run various kinds of programs on computers in
GCP's data center, and to make these computers accessible to
themselves or the public.

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

First, edit the configuration file
[common_config.sh](scripts/common_config.sh). Most defaults are
reasonable for a demo, but set at least:
- `tom_hostname`: the fully qualified domain name (public URL) of your TOM
- `certmanager_email`: email used by Let’s Encrypt via cert‑manager

The header of `common_config.sh` lists required variables; more context
is provided further down.

# Run the Scripts

First, set the name of your TOM. This should be the same as the one
you've created with make-tom.sh. This is required by both scripts run
below.

    export tom_name=YOUR_TOM_NAME_HERE
    export tom_hostname=YOUR_SITE_HOSTNAME_HERE

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

Once that is complete, deploy the Kubernetes cluster:

    export certmanager_email=YOUR_EMAIL_HERE 
    bash scripts/launch_kubernetes.sh

Similarly, it should be possible to continuously rerun the script
while fixing any issues that arise while running it.

# Install kubectl

Install kubectl to interact with your Kubernetes cluster:
- https://kubernetes.io/docs/tasks/tools/

# Create the Administrative Account

Create the administrative account. `kubectl` transparently manages
authentication for you. This command runs `manage.py createsuperuser`
inside the app pod to create a Django superuser. After this, use the
web UI to sign in with the new account.

	. scripts/common_config.sh
    kubectl -n "$kubernetes_namespace" exec -it deploy/demo-tom-deploy -c tom-deploy -- sh -lc 'python manage.py createsuperuser'

You only need to perform this action once after the server is running.

# Connecting to Your Instance

## Retrieving Your Static IP

After your cluster has started, you can use the following command to
retrieve the static IP address assigned to your django server

    . scripts/common_config.sh ; kubectl -n "$kubernetes_namespace" get ingress 

The IP address will be in the ADDRESS column.

## Configuring DNS

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
