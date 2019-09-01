pragma solidity ^0.5.8;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    uint airLineCount = 0;
    uint flightCount = 1;
    uint insuranceCount = 1;
    uint constant flightStatusDefault = 0;
    uint constant airlineApprovesMin = 4;

    struct Airline {
        uint id;
        bool feePaid;
        bool accepted;
        uint[] votes;
    }

    struct Flight {
        uint id;
        bytes32 key;
        address airline;
        string flightCode;
        uint departureTime;
        uint status;
        uint updatedTime;
    }

    enum InsuranceState {Valid, Expired, Refunded}
    struct Insurance{
        uint id;
        bytes32 flightId;
        uint amountPaid;
        address passenger;
        InsuranceState state;
    }

    mapping(address => Airline) airlines;
    mapping(bytes32 => Flight) flights;
    mapping(uint => Insurance) insurances;
    mapping(address => uint[]) airlinesFlights;
    mapping(bytes32 => uint[]) flightsInsurances;
    mapping(address => uint[]) passengersInsurances;
    mapping(address => uint) authorizedCallers;
    mapping(address => uint) passengersFund;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/
    event AirlineAdded(uint id, address airline);
    event AirlineVote(address candidate, address voter);
    event AirlinePaidFund(address airline, uint amount);
    event FlightAdded(uint id, address airline, string flightCode);
    event FlightCodeChanged(bytes32 key, uint status);
    event FlightStatusUpdated(bytes32 key, uint status, uint time);
    event InsuranceAdded(uint id, bytes32 flightId);
    event InsuranceRefunded(uint id);

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor() public {
        contractOwner = msg.sender;
        authorizedCallers[msg.sender] = 1;
        _registerAirline(msg.sender, msg.sender);
        airlines[msg.sender].feePaid = true;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _;
        // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireBeAnAirline(address airline) {
        require(airlines[airline].id != 0, "You must be an airline");
        _;
    }

    modifier requireAcceptedAirline(address airline) {
        require(airlines[airline].accepted, "To vote you must be accepted first");
        _;
    }

    modifier requirePaidAirline(address airline) {
        require(airlines[airline].feePaid, "To participate you must pay");
        _;
    }

    modifier requireAirlineOperable(address airline) {
        require(airlines[airline].feePaid && airlines[airline].accepted, "Airline isn't operable");
        _;
    }

    modifier requireAuthorized() {
        require(authorizedCallers[msg.sender] == 1, "You don't have authorization");
        _;
    }

    modifier didntVote(address candidate) {
        uint[] memory votes = airlines[candidate].votes;
        uint idApprover = airlines[msg.sender].id;

        bool found = false;
        for (uint i = 0; i < votes.length; i++) {
            if(votes[i] == idApprover){
                found = true;
                break;
            }
        }

        require (!found, "You already vote for this new Airline");
        _;
    }

    modifier requireNotRegistered(string memory flightCode, uint departureTimestamp, address airlineAddress) {
        bytes32 key = getFlightKey(airlineAddress, flightCode, departureTimestamp);
        require(flights[key].id == 0, "The flight has already been created!");
        _;
    }

    modifier requireFlight(bytes32 key) {
        require(flights[key].id > 0, "Flight must exist");
        _;
    }

    modifier requireInsurance(uint id) {
        require(insurances[id].id > 0, "Insurance doesn't exists");
        _;
    }

    modifier insuranceWithState(uint id, InsuranceState state) {
        require(insurances[id].state == state, "Insurance isn't on this state");
        _;
    }

    modifier isPassengerInsurance(uint id) {
        require(insurances[id].passenger == msg.sender, "You are not the insurance owner");
        _;
    }



    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isOperational() public view returns (bool) {
        return operational;
    }

    function isAirlineRegistered(address airline) public view returns (bool) {
        return airlines[airline].id > 0;
    }

    function isAirlineAccepted(address airline) public view returns (bool) {
        return airlines[airline].accepted;
    }

    function isAirlineFunded(address airline) public view returns (bool) {
        return airlines[airline].feePaid;
    }

    function isFlightRegistered(address airline, string memory flightCode, uint departureTime) public view returns (bool) {
        bytes32 key = getFlightKey(airline, flightCode, departureTime);
        return flights[key].id > 0;
    }

    function isPassengerInsured(address passenger, address airline, string memory flightCode, uint departureTime) public view returns (bool) {
        bool insured = false;
        bytes32 key = getFlightKey(airline, flightCode, departureTime);
        uint [] memory passengerInsurances = passengersInsurances[passenger];
        for (uint i = 0; i < passengerInsurances.length; i++) {
            if (insurances[passengerInsurances[i]].flightId == key) {
                insured = true;
                break;
            }
        }
        return insured;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(address airline, address elector) external requireIsOperational requireAuthorized requireBeAnAirline(elector) requireAcceptedAirline(elector) requirePaidAirline(elector){
        _registerAirline(airline, elector);
    }

    function _registerAirline(address airline, address elector) internal {
        airlines[airline].id = airLineCount;
        airlines[airline].feePaid = false;
        airlines[airline].accepted = airLineCount <= airlineApprovesMin;
        airlines[airline].votes.push(airlines[elector].id);
        airLineCount++;

        emit AirlineAdded(airlines[airline].id, airline);
    }

    function registerFlight(address airline, string calldata flightCode, uint departureTime) external requireIsOperational requireAuthorized requireAirlineOperable(airline) {
        bytes32 key = getFlightKey(airline, flightCode, departureTime);
        require(flights[key].id == 0, "must be a new Flight");

        Flight memory newFlight = Flight(flightCount, key, airline, flightCode, departureTime, flightStatusDefault, departureTime);
        flights[key] = newFlight;
        flightCount++;

        airlinesFlights[airline].push(newFlight.id);

        emit FlightAdded(newFlight.id, newFlight.airline, newFlight.flightCode);
    }

    function setFlightCode(bytes32 key, uint status, uint updateTime) external requireIsOperational requireAuthorized requireFlight(key) {
        flights[key].status = status;
        flights[key].updatedTime = updateTime;

        emit FlightCodeChanged(key, status);
    }

    function getFlight(string calldata _flightCode, uint departureTime, address airline) external view requireIsOperational requireAuthorized  returns (bytes32 key, address airlineAddress, string memory flightCode, uint departureStatusCode, uint departureTimestamp, uint updatedTimestamp){
        bytes32 _key = getFlightKey(airline, _flightCode, departureTime);
        Flight memory flight = flights[_key];
        return (flight.key, flight.airline, flight.flightCode, flight.status,  flight.departureTime, flight.updatedTime);
    }

    function getFlight(bytes32 _key) external view requireIsOperational requireAuthorized  returns (bytes32 key, address airlineAddress, string memory flightCode, uint departureStatusCode, uint departureTimestamp, uint updatedTimestamp){
        Flight memory flight = flights[_key];
        return (flight.key, flight.airline, flight.flightCode, flight.status,  flight.departureTime, flight.updatedTime);
    }

    function setFlightDepartureStatus(bytes32 key, uint departureStatus, uint updateTime) external requireIsOperational requireAuthorized requireFlight(key) {
        flights[key].status = departureStatus;
        flights[key].updatedTime = updateTime;

        emit FlightStatusUpdated(key, departureStatus, updateTime);
    }

    function buyInsurance(bytes32 flightId, address passenger) external payable requireIsOperational requireAuthorized requireFlight(flightId) {
        Insurance memory insurance = Insurance(insuranceCount, flightId, msg.value, passenger, InsuranceState.Valid);
        insurances[insuranceCount] = insurance;
        passengersInsurances[passenger].push(insurance.id);
        flightsInsurances[flightId].push(insurance.id);
        insuranceCount++;

        emit InsuranceAdded(insurance.id, insurance.flightId);
    }

    function getInsurance(uint id) external view requireIsOperational requireAuthorized returns (address passenger, uint amountPaid, uint insuranceState) {
        Insurance memory insurance = insurances[id];

        return (insurance.passenger, insurance.amountPaid, uint(insurance.state));
    }

    function getInsurancesFromFlight(bytes32 flightId) external view requireIsOperational requireAuthorized returns (uint[] memory _insurances) {
        return flightsInsurances[flightId];
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees(uint id, uint multiplier) external requireIsOperational requireAuthorized insuranceWithState(id, InsuranceState.Valid) {
        Insurance memory insurance = insurances[id];
        insurances[id].state = InsuranceState.Refunded;
        uint amountPaid = insurance.amountPaid;
        passengersFund[insurance.passenger] = passengersFund[insurance.passenger].add(multiplier.mul(amountPaid));

        emit InsuranceRefunded(id);
    }


    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address payable passenger) external payable requireIsOperational requireAuthorized {
        require(passengersFund[passenger] > 0, "Passenger doesn't have funds");
        uint toRefund = passengersFund[passenger];
        passengersFund[passenger] = passengersFund[passenger].sub(toRefund);

        passenger.transfer(toRefund);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund(address airline) public payable requireIsOperational requireAuthorized requireBeAnAirline(airline) {
        require(msg.value >= 10 ether, "You didn't pay enough");
        airlines[airline].feePaid = true;
        emit AirlinePaidFund(airline, msg.value);
    }

    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns (bytes32){
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    function voteAirline(address airline, address elector, uint minimum) public requireIsOperational requireAuthorized requireBeAnAirline(elector) requireAcceptedAirline(elector) requirePaidAirline(elector) didntVote(elector) {
        airlines[airline].votes.push(airlines[elector].id);
        airlines[airline].accepted = airlines[airline].votes.length > minimum;

        emit AirlineVote(airline, elector);
    }

    function authorizeContract(address addressToAuth) external requireIsOperational requireContractOwner {
        authorizedCallers[addressToAuth] = 1;
    }

    function deauthorizeContract(address dataContract) external requireIsOperational requireContractOwner {
        delete authorizedCallers[dataContract];
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() external payable {
        fund(msg.sender);
    }


}

