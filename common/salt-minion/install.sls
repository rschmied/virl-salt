salt-minion upgrade:
  file.managed:
    - name: /home/ubuntu/install_salt.sh
    - mode: 0755
    - source: "salt://install_salt.sh"
  cmd.run:
      - name: /home/ubuntu/install_salt.sh -P stable
