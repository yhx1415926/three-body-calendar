J/A+A/639/A77       Proxima Cen RV, FWHM and fluxes    (Suarez Mascareno+, 2020)
================================================================================
Revisiting Proxima with ESPRESSO.
    Suarez Mascareno A., Faria J.P., Figueira P., Lovis C., Damasso M.,
    Gonzalez Hernandez J.I., Rebolo R., Cristiano S., Pepe F.,Santos N.C.,
    Zapatero Osorio M.R., Adibekyan V., Hojjatpanah S., Sozzetti A.,
    Murgas F., Abreu M., Affolter M., Alibert Y., Aliverti M., Allart R.,
    Allende Prieto C., Alves D., Amate M., Avila G., Baldini V., Bandi T.,
    Barros S.C.C., Bianco A., Benz W., Bouchy F., Broeng C., Cabral A.,
    Calderone G., Cirami R., Coleho J., Conconi P., Coretti I., Cumani C.,
    Cupani G., D Odorico V.,  Deiries S., Delabre B., Di Marcantonio P.,
    Dumusque X., Ehrenreich D., Fragoso A., Genolet L., Genoni M.,
    Genova Santos R., Hughes I., Iwert O., Kerber F., Knusdrtrup J.,
    Landoni M., Lavie B., Lillo-Box J., Lizon J., Lo Curto G., Maire C.,
    Manescau A., Martins C.J.A.P., Megevand D., Mehner A., Micela G.,
    Modigliani A., Molaro P., Monteiro M.A., Monteiro M.J.P.F.G.,
    Moschetti M., Mueller E., Nunes N.J., Oggioni L., Oliveira A., Palle E.,
    Pariani  G., Pasquini L., Poretti E., Rasilla J.L., Redaelli E., Riva M.,
    Santana Tschudi S., Santin P., Santos P., Segovia A., Sosnowska D.,
    Sousa S., Snano P., Tenegi F., Udry S., Zanutta A., Zerbi F.
    <Astron. Astrophys. 639, A77 (2020)>
    =2020A&A...639A..77S        (SIMBAD/NED BibCode)
================================================================================
ADC_Keywords: Stars, double and multiple ; Stars, dwarfs ; Exoplanets ;
              Radial velocities
Keywords: techniques: radial velocity -
          planets and satellites: terrestrial planets - stars: activity -
          stars: low-mass - stars: individual: Proxima

Abstract:
    The discovery of Proxima b marked one of the most important milestones
    in exoplanetary science in recent years. Yet the limited precision of
    the available radial velocity data and the difficulty in modelling the
    stellar activity calls for a confirmation of the Earth-mass planet. We
    aimed to confirm the presence of Proxima b using independent
    measurements obtained with the new ESPRESSO spectrograph, and refine
    the planetary parameters taking advantage of its improved precision.
    We analysed 63 spectroscopic ESPRESSO observations of Proxima (Gl 551)
    taken during 2019. We obtained radial velocity measurements with a
    typical radial velocity photon noise of 26cm/s. We combined these
    data with archival spectroscopic observations and newly obtained
    photometric measurements to model the stellar activity signals and
    disentangle them from planetary signals in the radial velocity (RV)
    data. We ran a joint Markov chain Monte Carlo analysis on the time
    series of the RV and full width half maximum of the cross-correlation
    function to model the planetary and stellar signals present in the
    data, applying Gaussian process regression to deal with the stellar
    activity signals. We confirm the presence of Proxima b independently
    in the ESPRESSO data and in the combined ESPRESSO+HARPS+UVES dataset.
    The ESPRESSO data on its own shows Proxima b at a period of
    11.218+/-0.029-days, with a minimum mass of 1.29+/-0.13Me. In the
    combined dataset we measure a period of 11.18427+/-0.00070 days with a
    minimum mass of 1.173+/-0.086Me. We get a clear measurement of the
    stellar rotation period (87+/-12d) and its induced RV signal, but no
    evidence of stellar activity as a potential cause for the 11.2-days
    signal. We find some evidence for the presence of a second
    short-period signal, at 5.15-days with a semi-amplitude of only
    40cm/s. If caused by a planetary companion, it would correspond to a
    minimum mass of 0.29+/-0.08Me. We find that for the case of Proxima,
    the full width half maximum of the cross-correlation function can be
    used as a proxy for the brightness changes and that its gradient with
    time can be used to successfully detrend the RV data from part of the
    influence of stellar activity. The activity-induced RV signal in the
    ESPRESSO data shows a trend in amplitude towards redder wavelengths.
    Velocities measured using the red end of the spectrograph are less
    affected by activity, suggesting that the stellar activity is spot
    dominated. This could be used to create differential RVs that are
    activity dominated and can be used to disentangle activity-induced and
    planetary-induced signals. The data collected excludes the presence of
    extra companions with masses above 0.6Me at periods shorter than
    50-days.

Description:
    We obtained 67 individual spectra as part of the ESPRESSO GTO, as part
    of programme ID 1102.C-744 (PI: F.Pepe). Measurements were taken in
    ESPRESSO's 1UT high resolution (HR) mode with 15 minutes of
    integration time. More information on the different observing modes
    can be found on the ESO instrument page. ESPRESSO is equipped with its
    own pipeline providing extracted and wavelength-calibrated spectra, as
    well as RV measurements. The RV measurements are determined by a
    Gaussian fit of the cross-correlation function (CCF) of the spectrum
    with a binary mask computed from a stellar template. The mask was
    created using an ESPRESSO spectrum of Proxima as a template. Lines
    were identified through an automatic line-searching algorithm based on
    the spectrum derivative. The pipeline, version 2.0.0, is fully
    available to download from the ESO pipeline website.

    In combination with the ESPRESSO data we include the measurements
    taken between 2003 and 2017 with the High Accuracy Radial velocity
    Planet Searcher (HARPS) spectrograph. These data where obtained by the
    Geneva/Grenoble survey and the RedDots project, under programmes
    072.C-0488, 082.C-0718, 183.C-0437, 191.C-0505, 096.C-0082,
    099.C-0205, and 099.C-0880. This dataset is comprised of 196
    individual measurements that include two high cadence campaigns in
    2016 and 2017. The RVs were calculated using the TERRA package and
    have been obtained from. In 2015 HARPS was updated with new fibres,
    which improved its stability but also caused an RV offset with respect
    to previous measurements. For this reason we treat both HARPS datasets
    independently. The majority of the data were obtained without
    simultaneous calibration, which limits the stability of HARPS to a
    level of 1m/s.

    Along with the previous data we include the RVs taken with the
    Ultraviolet and Visual Echelle Spectrograph (UVES) and analysed in
    Dmasso et al. 2020. This dataset consists of 77 nightly binned UVES
    RVs obtained between 2000 and 2007. The UVES data were obtained in one
    of the early RV surveys for planets around M-dwarfs under ESO
    programme IDs: 65.L-0428, 66.C-0446, 267.C-5700, 68.C-0415, 69.C-0722,
    70.C-0044, 71.C-0498, 072.C-0495, 173.C-0606, and 078.C-0829 (PI: M.
    Kuerster). The data reduction and RV measurement is described in
    Butler et al., 2019AJ....158..251B. Cat. J/AJ/158/251). The UVES data
    do not include a measurement of the FWHM, as it is not easily
    available due to calibration by the iodine gas absorption cell.

Objects:
    --------------------------------------------
       RA   (2000)   DE       Designation(s)
    --------------------------------------------
    14 29 42.95  -62 40 46.2  Proxima = Gl 551
    --------------------------------------------

File Summary:
--------------------------------------------------------------------------------
 FileName      Lrecl  Records   Explanations
--------------------------------------------------------------------------------
ReadMe            80        .   This file
tablea1.dat       28      334   Radial velocity data
tablea2.dat       29      257   FWHM data
tablea3.dat       39      297   LCO Photometry
--------------------------------------------------------------------------------

See also:
 J/A+A/534/A133 : Proxima Cen chromospheric emission lines (Fuhrmeister+, 2011)
 J/A+A/603/A58  : Full spectrum of Proxima Centauri (Ribas+, 2017)
 J/AJ/153/93    : MOST photometry of Proxima (Kipping+, 2017)
 J/AJ/155/12    : Proxima Centauri photometry observed by BSST (Liu+, 2018)
 J/AJ/157/226   : Proxima Centauri photometry from 2006 to 2017 (Feliz+, 2019)
 J/A+A/626/A111 : Proxima Cen flare activity temporal changes (Pavlenko+, 2019)
 J/AJ/158/251   : New reduction of UVES data for 35 M dwarfs (Butler+, 2019)

Byte-by-byte Description of file: tablea1.dat
--------------------------------------------------------------------------------
   Bytes Format Units   Label     Explanations
--------------------------------------------------------------------------------
   3- 10  F8.3  d       BJD       Barycentric Julian date (BJD-2450000)
  13- 17  F5.2  m/s     DRV       Relative radial velocity
  21- 24  F4.2  m/s   e_DRV       Relative radial velocity uncertainty
      28  I1    ---     Spec      [0/4] Spectrograph (1)
--------------------------------------------------------------------------------
Note (1): Spectrograph as follows:
    0 = UVES
    1 = HARPS pre-upgrade
    2 = HARPS post-upgrade
    3 = ESPRESSO pre-upgrade
    4 = ESPRESSO post-upgrade
--------------------------------------------------------------------------------

Byte-by-byte Description of file: tablea2.dat
--------------------------------------------------------------------------------
   Bytes Format Units   Label     Explanations
--------------------------------------------------------------------------------
   3- 10  F8.3  d       BJD       Barycentric Julian date (BJD-2450000)
  13- 18  F6.2  m/s     DFWHM     Relative FWHM
  22- 25  F4.2  m/s   e_DFWHM     Relative FWHM uncertainty
      29  I1    ---     Spec      [1/4] Spectrograph (1)
--------------------------------------------------------------------------------
Note (1): Spectrograph as follows:
    1 = HARPS pre-upgrade
    2 = HARPS post-upgrade
    3 = ESPRESSO pre-upgrade
    4 = ESPRESSO post-upgrade
--------------------------------------------------------------------------------

Byte-by-byte Description of file: tablea3.dat
--------------------------------------------------------------------------------
   Bytes Format Units   Label     Explanations
--------------------------------------------------------------------------------
   3- 10  F8.3  d       BJD       Barycentric Julian date (BJD-2450000)
  15- 21  F7.5  ---     Flux      Relative Flux
  26- 32  F7.5  ---   e_Flux      Flux uncertainty
      39  I1    ---     Series    [1/3] Data series (1)
--------------------------------------------------------------------------------
Note (1): Data series as follows:
    1 = RedDots
    2 = LCO 1-m data
    3 = LCO 40-cm data
--------------------------------------------------------------------------------

Acknowledgements:
    Alejandro Suarez Mascareno, asm(at)iac.es

================================================================================
(End)                                        Patricia Vannier [CDS]  26-May-2020
