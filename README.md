# pix2pgp
## How to Run
Based on GHDL. Navigate to the ghdl/ dir and execute this to simply analyze the files:
```
$ bash ghdlRun.sh
```

If you want to run a testbench (here it is _Pix2PgpGearboxWrapperTb_), run:
```
$ bash ghdlRun.sh Pix2PgpGearboxWrapperTb
```
## Dependencies
You should have the following two packages in your server to run this:
```
* ghdl-llvm
* gtkwave
```