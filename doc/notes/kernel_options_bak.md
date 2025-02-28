## Notes
- Kernel options as per original image

```shell
cat /boot/firmware/cmdline.txt
console=serial0,115200 console=tty1 root=PARTUUID=b5376a11-02 rootfstype=ext4 fsck.repair=yes rootwait cfg80211.ieee80211_regdom=AU
```