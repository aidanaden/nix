{ config, pkgs, ... }:

{
  # Utility tools - OCI containers managed by Sablier (start/stop on demand)
  # These are lightweight tools that don't need to run 24/7

  # Stirling PDF - PDF manipulation toolkit
  virtualisation.oci-containers.containers.stirling-pdf = {
    image = "frooodle/s-pdf:0.36.0";
    ports = [ "9080:8080" ];
    environment = {
      TZ = "Asia/Singapore";
      DOCKER_ENABLE_SECURITY = "false";
    };
    extraOptions = [
      "--name=stirling-pdf"
      "--memory=512m"
    ];
  };

  # CyberChef - data analysis & encoding toolkit
  virtualisation.oci-containers.containers.cyberchef = {
    image = "ghcr.io/gchq/cyberchef:10.19.4";
    ports = [ "8916:80" ];
    extraOptions = [
      "--name=cyberchef"
      "--memory=256m"
    ];
  };

  # Squoosh - image compression
  virtualisation.oci-containers.containers.squoosh = {
    image = "pnmcosta/squoosh:latest";
    ports = [ "4411:8080" ];
    extraOptions = [
      "--name=squoosh"
      "--memory=256m"
    ];
  };

  # ConvertX - file format converter
  virtualisation.oci-containers.containers.convertx = {
    image = "ghcr.io/c4illin/convertx:v0.10.1";
    ports = [ "3242:3000" ];
    volumes = [
      "/config/convertx:/app/data"
    ];
    environment = {
      TZ = "Asia/Singapore";
    };
    extraOptions = [
      "--name=convertx"
      "--memory=512m"
    ];
  };

  # Vert - media file converter
  virtualisation.oci-containers.containers.vert = {
    image = "ghcr.io/cheeky-gorilla/vert:v5.2.2";
    ports = [ "7214:3000" ];
    extraOptions = [
      "--name=vert"
      "--memory=256m"
    ];
  };

  # Reubah - image manipulation
  virtualisation.oci-containers.containers.reubah = {
    image = "ghcr.io/joshuaepstein/reubah:latest";
    ports = [ "8088:8080" ];
    extraOptions = [
      "--name=reubah"
      "--memory=256m"
    ];
  };

  # IT-Tools - developer utilities collection (70+ tools)
  virtualisation.oci-containers.containers.it-tools = {
    image = "corentinth/it-tools:2024.10.22-7ca5933";
    ports = [ "8020:80" ];
    extraOptions = [
      "--name=it-tools"
      "--memory=128m"
    ];
  };
}
