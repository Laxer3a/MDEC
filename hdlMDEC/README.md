# MDEC

Attempt to do verilog Implementation of MDEC (Playstation 1)

# Documentation for MDEC

First work started with JPSXDEC :
https://github.com/m35/jpsxdec/blob/readme/jpsxdec/PlayStation1_STR_format.txt

Important blog post from JPSXDEC Author :
http://jpsxdec.blogspot.com/2010/09/psx-video-decoders-final-showdown.html

Used source code from MAME and PCSXR emulator for C implementation :
https://sites.google.com/site/lainpsxfiles/a/psx-video-deathmatch-20100906.zip

No$PSX Emulator Documentation :
https://problemkaputt.de/psx-spx.htm

Topics about the real hardware decap and implementation :
http://board.psxdev.ru/topic/9/

Do not plan to follow EXACT implementation (pointless to re-implement slower multiplier when you have one inside the FPGA).

Then of course, all the literature about the IDCT and possible fast transform.

See the /doc folder for more in-depth explaination.

# Comment on implementation.

IDCT is the core computation of the MDEC.
The most brute force algorithm is the 2D IDCT convolution. It requires 4096 multiply (and nearly half of additions if I am correct).
But, if done properly, IDCT is a separable filter. 
Which means that a 1D filter applied horizontally, then 1D applied vertically gives the same result
(at the condition of keeping all the bits during the computation)
In this case we go from a 8x8x8x8 iterations to 2x8x8x8 iterations, even using brute force.

Then for 1D convolution, there are some smarter algorithm ( ex, Yukihiro Arai &  Masayuki Nakajima 1988 : 'A Fast DCT-SQ Scheme for Images', behind paywall.
Ex Found also : https://jiaats.com/ojs31/index.php/eee/article/download/411/358/ )
But then COS table do not exist anymore.

PCSXR does have an implementation using a hardcoded sin convolution using Arai's algorithm.
The problem is then, that it is incompatible with MDEC spec, which authorize uploading the convolution tables. (the COS wave table)

MAME does implement a 2D BRUTE force version of it.

So, I have my own derived work from MAME source code using 2x1D IDCT. Then from that, implemented the verilog prototype (not committed, code really sucks)
I plan later to add both in C and verilog further logic and reduce the bit count to get the exact precision of the original hardware,
according to the comment of No$PSX emulator and people doing the reverse engineering effort at psxdev.ru

For now, my effort has been to get the same math as full precision implementation on PC in C.
Then do it in verilog.

# Comment and specification concerning timing.

The original PSX has to decode theoretically 320x240 frame @30 fps (we can lower down to 29.97 fps but...), and specs says you need 6x 8x8 IDCT block (2 Chroma, 4 Luma) to generate a single 16x16 RGB block decoded.
Which means that per frame, you have 20x15x6 IDCT block to perform, which raise to 54000 IDCT block per second (or 9000 16x16 RGB blocks if you prefer).
- For a single iteration, 2D brute force implementation, that would mean 54000 x 4096 cycle per second = 221.18 Mhz chip
- For a single iteration, using 1D pass x 2 = 54000 x 2x8x8x8 = 54000 x 1024 = 55.3 Mhz chip to do the job.

As we want to keep the table programmable as defined per spec, then we are force to parrallelize the work by implementing thing in hardware twice.
The choice from Sony seems to have separate a hardware for 1st and 2nd pass. Which means the execution time something like for n block, it takes [512 * (n+2)] cycles if we keep the pipeline busy with data.

In my case, I made the choice of having a single same hardware doing the 1st AND 2nd pass BUT TWICE faster, resulting in a [512xn] cycle of performance.
As I was/am not sure about what is correct for now about memory flow and latency, I opted for the fastest solution.
It makes the HW a bit harder, but actually the usage of resources is pretty neat. Memory wise (in bit count) it is the SAME as a TWO seperate pass solution,
and it also uses TWO accumulators and multiplier unit, (same as seperate pass would require anyway).

- For a doubly parallel iteration, using 1D pass x 2 x 2 = 54000 x 8x8x8 = 54000 x 512 = 27.65 Mhz chip to do the job.

So this should be enough to work with the main CPU clock @33.8 Mhz

I do have a feeling that my solution is a bit more elegant in term of HW requirement and perf. ratio but it takes a singular approach on how the table are accessed to output X/Y in correct order
at the end of the second pass. This drives how the memory must be organized (parrallel access to memory and how to structure the adresses) and everything else, including the COS table.

