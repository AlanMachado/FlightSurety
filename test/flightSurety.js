
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

    var config;
    let flightCode = '222222';
    let departureTime = Date.now();
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
        try {
          await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
        } catch(e) {
          accessDenied = true;
        }
        assert.equal(accessDenied, true, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

        // Ensure that access is allowed for Contract Owner account
        let accessDenied = false;
        try {
          await config.flightSuretyData.setOperatingStatus(false);
        } catch(e) {
          accessDenied = true;
        }
        assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

        await config.flightSuretyData.setOperatingStatus(false);

        let reverted = false;
        try{
          await config.flightSurety.setTestingMode(true);
        } catch(e) {
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
        } catch(e) {

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
            assert.equal(funded, false, "Airline should not be funded yet");
            await config.flightSuretyApp.fundAirline({from: newAirline, value: web3.utils.toWei('5', 'ether')});

            let isFunded = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
            assert.equal(isFunded, false, "Airline should still not be funded");
        } catch(e) {
        }

    });

    it('An airline can fund', async () => {
        // ARRANGE
        let newAirline = accounts[2];

        // ACT
        try {
            await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});

            let funded_pre = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
            assert.equal(funded_pre, false, "Airline should not be funded yet");
            await config.flightSuretyApp.fundAirline({from: newAirline, value: web3.utils.toWei('15', 'ether')});
            let isFunded = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
            assert.equal(isFunded, true, "Airline should be funded.");
        } catch(e) {
            console.log(e.message);
        }

    });

    it('A funded airline can register an Airline', async () => {
        // At this point in the test airline 1 is funded
        // ARRANGE
        let newAirline = accounts[1];

        let electorFunded = await config.flightSuretyApp.isAirlineFunded.call(config.firstAirline);
        assert.equal(electorFunded, true, "Elector is Funded");
        let electorRegistered = await config.flightSuretyApp.isAirlineRegistered.call(config.firstAirline);
        assert.equal(electorRegistered, true, "Elector is Registered");
        let electorAccepted = await config.flightSuretyApp.isAirlineAccepted.call(config.firstAirline);
        assert.equal(electorAccepted, true, "Elector is Accepted");

        // ACT
        try {
            await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
        } catch(e) {
            console.log(e.message);
        }

        // ASSERT
        let candidateFunded = await config.flightSuretyApp.isAirlineFunded.call(newAirline);
        assert.equal(candidateFunded, false, "Candidate isn't funded");
        let candidateRegistered = await config.flightSuretyApp.isAirlineRegistered.call(newAirline);
        assert.equal(candidateRegistered, true, "Candidate is registered");
        let candidateAccepted = await config.flightSuretyApp.isAirlineAccepted.call(newAirline);
        assert.equal(candidateAccepted, true, "Candidate is accepted");

    });

    it('Fifth registered airlines is not accepted but is registered', async () => {
        // At this point in the test airline 1 is funded
        // ARRANGE

        let fourthAirline = accounts[3];
        let fifthAirline = accounts[4];

        let fourthFunded = await config.flightSuretyApp.isAirlineFunded.call(fourthAirline);
        assert.equal(fourthFunded, false, "Fourth airline should not be funded");
        let fourthRegistered = await config.flightSuretyApp.isAirlineRegistered.call(fourthAirline);
        assert.equal(fourthRegistered, false, "Fourth should not be registered");
        let fourthAccepted = await config.flightSuretyApp.isAirlineAccepted.call(fourthAirline);
        assert.equal(fourthAccepted, false, "Fourth should not be accepted");
        let fifthFunded = await config.flightSuretyApp.isAirlineFunded.call(fifthAirline);
        assert.equal(fifthFunded, false, "Fifth should not be funded");
        let fifthRegistered = await config.flightSuretyApp.isAirlineRegistered.call(fifthAirline);
        assert.equal(fifthRegistered, false, "Fifth should not be registered");
        let fifthAccepted = await config.flightSuretyApp.isAirlineAccepted.call(fifthAirline);
        assert.equal(fifthAccepted, false, "Fifth should not be accepted");

        // ACT
        try {
            await config.flightSuretyApp.registerAirline(fourthAirline, {from: config.firstAirline});
            await config.flightSuretyApp.registerAirline(fifthAirline, {from: config.firstAirline});
        } catch(e) {
            console.log(e.message);
        }

        // ASSERT
        fourthFunded = await config.flightSuretyApp.isAirlineFunded.call(fourthAirline);
        assert.equal(fourthFunded, false, "Fourth should still not be funded");
        fourthRegistered = await config.flightSuretyApp.isAirlineRegistered.call(fourthAirline);
        assert.equal(fourthRegistered, true, "Fourth should be registered");
        fourthAccepted = await config.flightSuretyApp.isAirlineAccepted.call(fourthAirline);
        assert.equal(fourthAccepted, true, "Fourth should be accepted");
        fifthFunded = await config.flightSuretyApp.isAirlineFunded.call(fifthAirline);
        assert.equal(fifthFunded, false, "Fifth should still not be funded");
        fifthRegistered = await config.flightSuretyApp.isAirlineRegistered.call(fifthAirline);
        assert.equal(fifthRegistered, true, "Fifth should be registered");
        fifthAccepted = await config.flightSuretyApp.isAirlineAccepted.call(fifthAirline);
        assert.equal(fifthAccepted, false, "Fifth should not be accepted");

    });

    it('Nominate the fifth airline four times so its accepted', async () => {
        // Fund the first 4 airlines
        // ARRANGE
        let firstAirline = accounts[0];
        let secondAirline = accounts[1];
        let thirdAirline = accounts[2];
        let fourthAirline = accounts[3];
        let fifthAirline = accounts[4];

        try {
            await config.flightSuretyApp.fundAirline({from: secondAirline, value: web3.utils.toWei('10', 'ether')});
            //await config.flightSuretyApp.fundAirline({from: thirdAirline, value: web3.utils.toWei('10', 'ether')}); already funded
            await config.flightSuretyApp.fundAirline({from: fourthAirline, value: web3.utils.toWei('10', 'ether')});

            let firstFunded = await config.flightSuretyApp.isAirlineFunded.call(firstAirline);
            let secondFunded = await config.flightSuretyApp.isAirlineFunded.call(secondAirline);
            let thirdFunded = await config.flightSuretyApp.isAirlineFunded.call(thirdAirline);
            let fourthFunded = await config.flightSuretyApp.isAirlineFunded.call(fourthAirline);
            assert.equal(firstFunded, true, "First airline should be funded");
            assert.equal(secondFunded, true, "Second airline should be funded");
            assert.equal(thirdFunded, true, "Third airline should be funded");
            assert.equal(fourthFunded, true, "Fourth airline should be funded");

            let fifthAccepted = await config.flightSuretyApp.isAirlineAccepted.call(fifthAirline);
            assert.equal(fifthAccepted, false, "Fifth should not be accepted yet");

            await config.flightSuretyApp.registerAirline(fifthAirline, {from: firstAirline});
            await config.flightSuretyApp.registerAirline(fifthAirline, {from: secondAirline});
            await config.flightSuretyApp.registerAirline(fifthAirline, {from: thirdAirline});
            await config.flightSuretyApp.registerAirline(fifthAirline, {from: fourthAirline});

            fifthAccepted = await config.flightSuretyApp.isAirlineAccepted.call(fifthAirline);
            assert.equal(fifthAccepted, true, "Fifth airline should now be accepted");
        } catch(e) {
            console.log(e.message);
        }

    });

    it('Register a flight', async () => {
        let airline = accounts[1];


        let flightRegistered = await config.flightSuretyApp.isFlightRegistered.call(airline,flightCode,departureTime);
        assert.equal(flightRegistered, false, "flight should not be registered yet");

        try {
            await config.flightSuretyApp.registerFlight(flightCode,departureTime, {from: airline});
            flightRegistered = await config.flightSuretyApp.isFlightRegistered.call(airline,flightCode,departureTime);
            assert.equal(flightRegistered, true, "flight should be registered");
        } catch(e) {
            console.log(e.message);
        }
    });

    it('Passenger can buy insurance', async ()=> {
        let passenger = accounts[7];
        let airline = accounts[1];
        try {
            flightRegistered = await config.flightSuretyApp.isFlightRegistered.call(airline,flightCode,departureTime);
            assert.equal(flightRegistered, true, "flight should be registered");

            let passenger1_insured = await config.flightSuretyApp.isPassengerInsured.call(passenger, airline, flightCode, departureTime, {from: config.firstAirline});
            assert.equal(passenger1_insured, false, "passenger should not be insured yet");

            await config.flightSuretyApp.InsureFlight(airline,flightCode,departureTime, {from: passenger, value: web3.utils.toWei('1', 'ether')});

            passenger1_insured = await config.flightSuretyApp.isPassengerInsured.call(passenger, airline, flightCode, departureTime, {from: config.firstAirline});
            assert.equal(passenger1_insured, true, "passenger should be insured ");
        } catch (e) {
            console.log(e.message);
        }
    });

    it('If flight is late credit passenger', async () => {
        let passenger = accounts[7];
        let airline = accounts[1];
        let callpaywith0balance = true;

        try {
            await config.flightSuretyApp.withdrawCredits({from: passenger});
        }
        catch(e){
            console.log(e.message);
            callpaywith0balance = false;
        }

        assert.equal(callpaywith0balance, false, "Should not be able to call pay with no credit balance");

        try {
            callpaywith0balance = true;
            await config.flightSuretyApp.testProcessFlightStatus(airline, flightCode, departureTime, config.STATUS_CODE_LATE_AIRLINE);
            await config.flightSuretyApp.withdrawCredits({from: passenger});

        } catch(e){
            console.log(e);
            callpaywith0balance = false;
        }

        assert.equal(callpaywith0balance, true, "withdraw worked correctly");

    });



});
