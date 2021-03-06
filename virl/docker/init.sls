## Install docker with registry running in container and docker-py for docker API
{% set registry_ip = salt['pillar.get']('virl:l2_address2', salt['grains.get']('l2_address2', '172.16.2.254/xx' )).split('/')[0] %}
{% set registry_port = salt['pillar.get']('virl:docker_registry_port', salt['grains.get']('docker_registry_port', '19397' )) %}

{% set docker_version = '1.9.1-0~trusty' %}
{% set registry_version = '2.4.0' %}
{% set registry_file = 'registry-2.4.0.tar' %}
{% set registry_file_hash = '0c79a98a8a2954c3bc04388be22ec0f5' %}
# If updating registry load registry manually into docker and get its Docker ID by issue $docker images
{% set registry_docker_ID = '0f29f840cdef' %}
{% set tapcounter_docker_ID = 'fd89e345206b' %}

{% set download_proxy = salt['pillar.get']('virl:download_proxy', salt['grains.get']('download_proxy', '')) %}
{% set download_no_proxy = salt['pillar.get']('virl:download_no_proxy', salt['grains.get']('download_no_proxy', '')) %}


{% from "virl.jinja" import virl with context %}

docker registry settings:
  cmd.run:
    - names:
      - crudini --set /etc/virl/common.cfg host docker_registry_ip {{ registry_ip }}
      - crudini --set /etc/virl/common.cfg host docker_registry_port {{ registry_port }}

# Docker:

remove_wrong_docker:
  pkg.purged:
    - name: lxc-docker

docker_repository:
  file.managed:
    - name: /etc/apt/sources.list.d/virl-docker.list
    - mode: 0755
    - contents: |
        deb http://apt.dockerproject.org/repo ubuntu-trusty main

docker_repository_key:
  cmd.run:
    - names:
      - apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

docker_pin:
  file.managed:
    - name: /etc/apt/preferences.d/virl-docker
    - mode: 0755
    - contents: |
        Package: docker-engine
        Pin: version {{ docker_version }}
        Pin-Priority: 1001
    - required_in:
      - pkg: docker_install

docker_remove:
  pkg.removed:
    - name: docker-engine

docker_install:
  pkg.installed:
    - refresh: True
    - name: docker-engine
    - require:
      - file: docker_repository
      - cmd: docker_repository_key
      - file: docker_pin
      - pkg: docker_remove

include:
  - virl.docker.config

# docker-py:

docker-py:
  pip.installed:
    - name: docker-py
    {% if virl.proxy  %}
    - proxy: {{ virl.http_proxy }}
    {% endif %}

# add registry into docker:

registry_remove:
  cmd.script:
    - source: salt://virl/files/remove_docker_registry.sh
    - env:
      REGISTRY_ID: {{ registry_docker_ID }}
      REGISTRY_IP: {{ registry_ip }}
      REGISTRY_PORT: {{ registry_port }}
    - require:
      - pkg: docker_install
      - module: docker_restart

registry_load:
  # state docker.loaded is buggy -> file.managed and cmd.run
  file.managed:
    - name: /var/cache/virl/docker/registry.tar
    - makedirs: True
    - source: salt://images/salt/{{ registry_file }}
    - source_hash: {{ registry_file_hash }}
    - unless: docker images -q | grep {{ registry_docker_ID }}
  cmd.run:
    - names:
      - docker load -i /var/cache/virl/docker/registry.tar
    - unless: docker images -q | grep '{{ registry_docker_ID }}'

registry_tag:
  cmd.run:
    - names:
      - docker tag {{ registry_docker_ID }} registry:{{ registry_version }}
    - unless: docker images | grep '^registry *{{ registry_version }} *{{ registry_docker_ID }}'
    - require:
      - cmd: registry_load

registry_run:
  # dockerio.running replaced by cmd.run due to API problems of dockerio/docker-py used versions
  cmd.run:
    - names:
      - docker run -d -p {{ registry_ip }}:{{ registry_port }}:5000 -e REGISTRY_STORAGE_DELETE_ENABLED=true -e REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/var/lib/registry -v /var/local/virl/docker:/var/lib/registry --restart=always registry:{{ registry_version }}
    - require:
      - cmd: registry_tag
    # - unless: docker ps | grep "{{ registry_ip }}:{{ registry_port }}->5000/tcp"

# Docker tap-counter
virl-tap-counter:latest:
  # this remembers previously used registry IP:port and restores it,
  # don't include them or it will cause issues when IP/port changes
  dockerng.image_present:
    - load: salt://images/salt/docker-tap-counter.tar
    - force: True
  cmd.run:
    - names:
      - docker tag -f {{ tapcounter_docker_ID }} {{ registry_ip }}:{{ registry_port }}/virl-tap-counter:latest
      - docker push {{ registry_ip }}:{{ registry_port }}/virl-tap-counter:latest
    - require:
      - cmd: registry_run

virl_tap_counter_clean:
  cmd.run:
    - names:
      - docker rmi {{ registry_ip }}:{{ registry_port }}/virl-tap-counter:latest
      - docker rmi virl-tap-counter:latest
      - docker rmi {{ tapcounter_docker_ID }} || true
