{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Kernel modules
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # CPU microcode
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # CPU frequency scaling - use schedutil for balanced performance
  powerManagement.cpuFreqGovernor = "schedutil";

  # Hardware info:
  # - Intel Core i5-2400S (Sandy Bridge, 4 cores)
  # - 16GB RAM
  # - Samsung SSD 870 EVO 250GB (OS)
  # - 8x WD Red HDDs (data)
}
