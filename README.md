Note Not This Whole Script I Own Or Created I Just change th OS (Distro)
- Hopingboyz Owns the 80% of the script
- I Own 20% Because of cloud image and changes in start.sh
Probably This Script Is Just For My new Trick

```git clone https://github.com/FrancisRozario760/Debian-12.git```
```cd Debian-12```
```- docker build -t debian-vm .```
```- docker run --privileged -p 6080:6080 -p 2221:2221 \
    -v $PWD/vmdata:/data debian-vm
