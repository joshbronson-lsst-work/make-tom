# make-tom

`make-tom-sh` is a shell script for creating a TOM Toolkit-based TOM in a virtual environment. It's useful both as a way to spin up an "out-of-the-box" TOM for evaluation and as a reference for how to create a TOM for further customization and development.

## Usage
The `make-tom.sh` script is all you need. Download it, make it executable (`chmod +x make-tom.sh`), and run it:
```bash
  ./make-tom.sh my_tom
```
This will create the directory `my_tom` in your current working directory with a virtural environment (`my_tom/env`) and TOM Toolkit (Django) project.

The basic workflow executed by the `make-tom.sh` script is:
1. Create a Python virtual environment and activate it.
2. From PyPI, install `tomtoolkit` and its dependencies (including Django) into the virtual environment.
3. Use the `django-admin startproject` command to create a basic Django project.
4. Add the one-time utility, `tom_setup`, to the basic Django project's `settings.py` `INSTALLED_APPS` list and run its `tom_setup` management command.

When the `make-tom.sh` script is finished, you'll see (for example) the following output:

```bash
Here is the directory we created:
/path/to/your/cwd//my_tom
.
├── data
├── db.sqlite3
├── manage.py
├── my_tom
│   ├── asgi.py
│   ├── __init__.py
│   ├── __pycache__
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
├── static
├── templates
└── tmp

6 directories, 7 files

Next steps:
  1. cd to the new directory. 
  2. activate the virtual environment with 'source ./env/bin/activate'. 
  3. Start the Django development server with './manage.py runserver'. 
  4. Point a browser to the URL given by the 'runserver' management command.
```

### Tips and Trouble-shooting

Here's a way to generate a uniquely named TOM, which can be useful when you repeatedly want to evaluate or experiment with something with the intention of deleting the directory when you're done:
```bash
./make-tom.sh name_of_your_tom_`date +'%Y%h%d_%0k%M'`
```
This will create a uniquely named TOM Toolkit directory called, for example, `name_of_your_tom_2023Dec13_1751`.

# Creating an Externally Facing TOM
Creating an externally-facing TOM can be done in a few different
ways. The basic ingredents include the following:
* a domain name and control over DNS entries for that domain
* a platform on which you can spin up a Kubernetes cluster and a
  static IP address.

There are many ways to gather these ingredients, and users should
decide for themselves how to gather them. However, there are
instructions [here](deployment.md) to deploy an external TOM if you
are willing to use the following kinds of ingredients:
* a domain name and control over DNS entries for that domain:
  Squarespace. (You can easily use your own DNS server, though, if you
  have the ability to create DNS A records for hosts for which you
  have matching TLS keys at your organization.)
* a platform on which you can spin up a Kubernetes cluster and a
  static IP address: Google Compute Platform

This isn't an endorsement of these particular tools, and many other
fine alternatives exist for each of them.
