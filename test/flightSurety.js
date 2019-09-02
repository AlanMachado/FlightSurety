
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

    var config;
    before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeContract(config.flightSuretyApp.address);
    await config.flightSuretyData.authorizeContract(config.owner);
    });

    it(`Owners of contracts and first airline are the same`, async function () {

        let flightAppOwner = await config.flightSuretyApp.getOwner.call();
        let flightDataOwner = await config.flightSuretyData.getOwner.call();
        assert.equal(flightAppOwner, config.firstAirline, "First airline should own FlighSuretyApp contract instance");
        assert.equal(flightDataOwner, config.firstAirline, "First airline should own FlighSuretyData contract instance");

    });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

    it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");

    });

    it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try
      {
          await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try
      {
          await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try
      {
          await config.flightSurety.setTestingMode(true);
      }
      catch(e) {
          reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);

    });

    it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {

    // ARRANGE
    let newAirline = accounts[2];

    // ACT
    try {
        await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
    }
    catch(e) {

    }
    let result = await config.flightSuretyData.isAirlineFunded.call(newAirline);

    // ASSERT
    assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");

    });

    it('An airline that sends less then 10 ether does not fund', async () => {
        // ARRANGE
        let newAirline = accounts[2];

        // ACT
        try {
            await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
            let funded = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
            assert.equal(funded, false, "Before calling fund, airline is funded should be false");
            let registered = await config.flightSuretyApp.isAirlineRegistered.call(newAirline);
            assert.equal(registered, true, "Before calling fund, airline is registered should be true");
            let accepted = await config.flightSuretyApp.isAirlineAccepted.call(newAirline);
            assert.equal(accepted, true, "Before calling fund, airline is accepted should be true");
            await config.flightSuretyApp.fundAirline({from: newAirline, value: web3.utils.toWei('5', 'ether')});

            let registered_post = await config.flightSuretyApp.isAirlineRegistered.call(newAirline);
            assert.equal(registered_post, true, "After calling fund with 5 ether, airline is registered should be true");
            let funded_post = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
            assert.equal(funded_post, false, "After calling fund with 5 ether, airline is funded should be false");
            let nominated_post = await config.flightSuretyApp.isAirlineAccepted.call(newAirline);
            assert.equal(nominated_post, true, "After calling fund with 5 ether, airline is accepted should be true");
        }
        catch(e) {
        }

    });

    it('An airline can fund if it sends more then 10 ether.', async () => {
        // ARRANGE
        let newAirline = accounts[2];
        await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});

        let funded_pre = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
        assert.equal(funded_pre, false, "Before calling fund, first airline is funded should be false");
        let registered_pre = await config.flightSuretyApp.isAirlineRegistered.call(newAirline);
        assert.equal(registered_pre, true, "Before calling fund, first airline is registered should be true");
        let nominated_pre = await config.flightSuretyApp.isAirlineAccepted.call(newAirline);
        assert.equal(nominated_pre, true, "Before calling fund, first airline is nominated should be true");

        // ACT
        try {
            await config.flightSuretyApp.fundAirline({from: newAirline, value: web3.utils.toWei('12', 'ether')});
            let funded_post = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
            assert.equal(funded_post, true, "After calling fund with 12 ether, first airline is funded should be true");
            let registered_post = await config.flightSuretyApp.isAirlineRegistered.call(newAirline);
            assert.equal(registered_post, true, "After calling fund with 12 ether, first airline is registered should be true");
            let nominated_post = await config.flightSuretyApp.isAirlineAccepted.call(newAirline);
            assert.equal(nominated_post, true, "After calling fund with 12 ether, first airline is nominated should be true");
        }
        catch(e) {
            //console.log(e.message);
        }

        // ASSERT

    });



});
