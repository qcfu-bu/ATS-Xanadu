# [ATS3](http://www.ats-lang.org/) - ATS/Xanadu

A Programming Language System to Unleash the Potentials of Types
and Templates

## Build Status

* [![Build Status](https://travis-ci.org/githwxi/ATS-Xanadu.svg?branch=master)](https://travis-ci.org/githwxi/ATS-Xanadu) Ubuntu
* [![Build Status](https://ci.appveyor.com/api/projects/status/github/githwxi/ats-xanadu?branch=master&svg=true)](https://ci.appveyor.com/project/githwxi/ats-xanadu/branch/master) Cygwin

## Project Description

ATS3 is an attempt to greatly improve upon ATS2.

Probably the biggest problem with ATS2 is the *very* steep learning
curve associated with it.  Very few programmers were able to ever
overcome it to reach the point where they could truly start enjoying
the tremendous power of (advanced) type-checking and (embeddable)
templates.

When DML (the predecessor of ATS) was designed nearly 20 years ago, a
two-layered approach to type-checking was taken: ML-like type-checking
first and dependent type-checking second.  This approach was later
abandoned in the design of ATS. Instead, there is only dependent
type-checking in ATS1 and ATS2. In ATS3, DML's two-layered approach is
to be adopted. In particular, a program in ATS3 that passes ML-like
type-checking can be compiled and executed. So one can skip dependent
type-checking in ATS3 if one so chooses. In this way, the learning
curve is expected to be greatly leveled. But there is much more than
just leveling the learning curve.

ML-like types are algebraic (involving no explicit quantifiers). Such
types are so much friendlier than dependent types (which often involve
explicit quantifiers) for supporting type-based meta-programming.  It
seems that a chance has finally arrived to properly address the
problem of template instance resolution that causes so much annoyance
in ATS2 (due to the very use of dependent types for template selection).

In short, ATS3 adds an extra layer to ATS2 for supporting ML-like
algebraic type-checking. Type-based meta-programming in ATS3 solely
uses algebraic types (while ATS2 uses dependent types).

## Installing ATS3

ATS3 is not ready for release yet.

Please see
[http://www.ats-lang.org/Downloads.html](http://www.ats-lang.org/Downloads.html) for
instructions after it is officially released.

## Developing ATS3

## Documenting ATS3

## Licenses for ATS/Xanadu

* The Compiler (ATS/Xanadu):
  [GPLv3](https://github.com/githwxi/ATS-Xanadu/blob/master/COPYING-gpl-3.0.txt)
* The ATS source for the Libraries (ATSLIB/{prelude,xatslib}):
  [LGPLv3](https://github.com/githwxi/ATS-Xanadu/blob/master/COPYING-lgpl-3.0.txt).
* As a special exception, any C code generated by the Compiler based on the Libraries
  source is not considered *by* *default* to be licensed under GPLv3/LGPLv3. If you use
  such C code together with other code to create an executable, then the C code by itself
  does not cause the executable to be covered by GPLv3/LGPLv3. However, there may be reasons
  unrelated to using ATS that can result in the executable being covered by GPLv3/LGPLv3.
* The contributed portion (ATS/Xanadu/contrib) is released under the MIT license.
* There is also a release under the MIT license for the C header files of the Libraries,
  which one can, for instance, freely insert into C code generated from ATS source code.
