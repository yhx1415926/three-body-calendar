J/AJ/162/14  Astrometry & radial velocity, Alpha Centauri system (Akeson+, 2021)
================================================================================
Precision millimeter astrometry of the {alpha} Centauri AB system.
    Akeson R., Beichman C., Kervella P., Fomalont E., Benedict G.F.
   <Astron. J., 162, 14-14 (2021)>
   =2021AJ....162...14A    (SIMBAD/NED BibCode)
================================================================================
ADC_Keywords: Stars, double and multiple; Stars, G-type; Positional data;
              Photometry, millimetric/submm; Optical; Radial velocities
Keywords: Fundamental parameters of stars; Main sequence stars; Radio astrometry
          Astrometric binary stars

Abstract:
    Alpha Centauri A is the closest solar-type star to the Sun and offers
    the best opportunity to find and ultimately to characterize an
    Earth-sized planet located in its habitable zone. Here, we describe
    initial results from an Atacama Large Millimeter/submillimeter Array
    (ALMA) program to search for planets in the {alpha} Cen AB system
    using differential astrometry at millimeter wavelengths. Our initial
    results include new absolute astrometric measurements of the proper
    motion, orbital motion and parallax of the {alpha} Cen system. These
    lead to an improved knowledge of the physical properties of both
    {alpha} Cen A and B. Our estimates of ALMA's relative astrometric
    precision suggest that we will ultimately be sensitive to planets of a
    few tens of Earth mass in orbits from 1 to 3au, where stable orbits
    are thought to exist.

Description:
    We obtained a series of Atacama Large Millimeter/submillimeter Array
    (ALMA) observations of {alpha} Cen in Cycle 6 between 2018 October and
    2019 August at band 7, using the nominal continuum set-up of four
    1.9GHz spectral windows at frequencies 336.5, 338.5, 348.5, and
    350.5GHz.

    We adopted radial velocity data from the large series of High Accuracy
    Radial velocity Planet Searcher (HARPS) measurements of {alpha} Cen A
    and B obtained since 2004, publicly available from the ESO archive.

Objects:
    ---------------------------------------------------------
       RA   (2000)   DE        Designation(s)
    ---------------------------------------------------------
    14 39 36.49  -60 50 02.4   Alpha Centauri A = * alf Cen A
    14 39 35.06  -60 50 15.1   Alpha Centauri B = * alf Cen B
    ---------------------------------------------------------

File Summary:
--------------------------------------------------------------------------------
 FileName    Lrecl    Records    Explanations
--------------------------------------------------------------------------------
ReadMe          80          .    This file
table6.dat      53        106    Relative astrometry of alpha Cen B with respect
                                  to A
table7.dat      36      17567    Radial velocity measurements for alpha Cen A
                                  and B from the HARPS instrument
table12.dat    123        801    Ephemeris of alpha Cen A and B between 2010 and
                                  2050
--------------------------------------------------------------------------------

See also:
 I/237 : The Washington Visual Double Star Catalog, 1996.0 (Worley+, 1996)
 I/311 : Hipparcos, the New Reduction (van Leeuwen, 2007)
 J/A+AS/107/235 : Photographic observations of visual binaries (Jasinta+, 1994)
 J/ApJ/687/1264 : Age estimation for solar-type dwarfs (Mamajek+, 2008)
 J/ApJ/771/40 : Main-sequence A, F, G, and K stars photometry (Boyajian+, 2013)
 J/A+A/615/A172 : alpha Cen A and B chemical composition (Morel, 2018)
 J/AJ/155/24 : Radial velocity & planet detectability in alpha Cen (Zhao+, 2018)

Byte-by-byte Description of file: table6.dat
--------------------------------------------------------------------------------
   Bytes Format Units    Label  Explanations
--------------------------------------------------------------------------------
   1-  9 F9.4   yr       Date   [1940/2020] Epoch of observation
  11- 18 F8.4   deg      PA     [6.5/350] Position angle
  20- 25 F6.4   deg    e_PA     [0.003/4.3] Uncertainty in PA
  27- 34 F8.5   arcsec   Sep    [2.03/22] Separation
  36- 42 F7.5   arcsec e_Sep    [0.0003/0.5] Uncertainty in sep
  44- 53 A10    ---      Ref    Reference (1)
--------------------------------------------------------------------------------
Note (1): References as follow:
      K16 = Kervella+, 2016A&A...594A.107K
 K16/ALMA = Kervella+, (2016) measurements of data from
            Liseau+, 2015A&A...573L...4L
     An15 = Anton, 2015JDSO...11...81A
     An14 = Anton, 2014JDSO...10..232A
     An12 = Anton, 2012JDSO....8...15A
     An11 = Anton, 2011JDSO....7...64A
     An08 = Anton, 2008JDSO....4...40A
     An06 = Anton, 2006JDSO....2..108A
      WDS = Washington Double Star Catalog, Worley and Douglass, 1996, I/237
     vL07 = Van Leeuwen+, 2007, I/311
      J94 = Jasinta and Soegiartini, 1994, J/A+AS/107/235
      P91 = Panjaitan and Herdiwijaya, 1991A&AS...88...63P
      T85 = Torres, 1985A&AS...59..449T
      F86 = Frengetto, Webb Society Handbook, 1986
--------------------------------------------------------------------------------

Byte-by-byte Description of file: table7.dat
--------------------------------------------------------------------------------
   Bytes Format Units   Label  Explanations
--------------------------------------------------------------------------------
   1- 11 F11.5  d       MJD    [53039/58242] Modified Julian Date; MJD-2400000.5
      14 A1     ---     ID     Star identifier; A or B
  16- 25 F10.5 km/s     RVel   [-24.89/-21.83] Radial Velocity (1)
  30- 36 F7.5  km/s   e_RVel   [0.002/0.01] Uncertainty in RVel
--------------------------------------------------------------------------------
Note (1): Radial velocity measurements from the HARPS instrument taken from the
          ESO archive. Filtered and correct as described in section 3.1.2.
--------------------------------------------------------------------------------

Byte-by-byte Description of file: table12.dat
--------------------------------------------------------------------------------
   Bytes Format Units    Label  Explanations
--------------------------------------------------------------------------------
   1-  7 F7.2   yr       Date   [2010/2050] Decimal year
   9- 10 I2     h        CRAh   [14] Hour of center of mass Right Ascension
  12- 13 I2     min      CRAm   [39] Minute of center of mass Right Ascension
  15- 21 F7.4   s        CRAs   [11/31] Second of center of mass Right Ascension
      23 A1     ---      CDE-   [-] Sign of center of mass Declination
  24- 25 I2     deg      CDEd   [60] Degree of center of mass Declination
  27- 28 I2     arcmin   CDEm   [49/50] Arcminute of center of mass Declination
  30- 35 F6.3   arcsec   CDEs   Arcsecond of center of mass Declination
  37- 38 I2     h        ARAh   [14] Star A hour of Right Ascension
  40- 41 I2     min      ARAm   [39] Star A minute of Right Ascension
  43- 49 F7.4   s        ARAs   [11/32] Star A second of Right Ascension
      51 A1     ---      ADE-   [-] Star A sign of Declination
  52- 53 I2     deg      ADEd   [60] Star A degree of Declination
  55- 56 I2     arcmin   ADEm   [49] Star A arcminute of Declination
  58- 63 F6.3   arcsec   ADEs   [24/60] Star A arcsecond of Declination
  65- 66 I2     h        BRAh   [14] Star B hour of Right Ascension
  68- 69 I2     min      BRAm   [39] Star B minute of Right Ascension
  71- 77 F7.4   s        BRAs   [10/31] Star B second of Right Ascension
      79 A1     ---      BDE-   [-] Star B sign of Declination
  80- 81 I2     deg      BDEd   [60] Star B degree of Declination
  83- 84 I2     arcmin   BDEm   [49/50] Star B arcminute of Declination
  86- 91 F6.3   arcsec   BDEs   Star B arcsecond of Declination
  94- 99 F6.3   arcsec   dRa    [-7.68/4.12] RA offset of B relative to A
 101-107 F7.3   arcsec   dEC    [-16.8/9.78] Dec offset of B relative to A
 109-114 F6.3   arcsec   Sep    [1.69/18.5] A-B separation
 117-123 F7.3   deg      PA     [0.13/360] A-B position angle
--------------------------------------------------------------------------------

History:
    From electronic version of the journal

================================================================================
(End)                          Prepared by [AAS], Coralie Fix [CDS], 08-Nov-2021
