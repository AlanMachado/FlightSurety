pragma solidity ^0.4.25;

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
    uint constant minToAccept = 5;
    uint constant flightStatusDefault = 0;

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

    enum InsuranceState {Sleeping, Expired, Refunded}
    struct Insurance{
        uint id;
        uint flightId;
        uint amountPaid;
        address passenger;
        InsuranceState state;
    }

    mapping(address => Airline) airlines;
    mapping(bytes32 => Flight) flights;
    mapping(uint => Insurance) insurances;
    mapping(address => uint[]) airlinesFlights;
    mapping(uint => uint[]) flightsInsurances;
    mapping(address => uint[]) passengersInsurances;
    mapping(address => bool) authorizedCallers;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/
    event AirlineAdded(uint id, address airline);
    event AirlineVote(address candidate, address voter);
    event AirlinePaidFund(address airline, uint amount);
    event FlightAdded(uint id, address airline, string flightCode);
    event FlightCodeChanged(bytes32 key, uint status);

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor() public {
        contractOwner = msg.sender;
        _registerAirline(msg.sender);
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

    modifier requireBeAnAirline() {
        require(airlines[msg.sender] != address(0), "You must be an airline");
        _;
    }

    modifier requireAcceptedAirline() {
        require(airlines[msg.sender].accepted, "To vote you must be accepted first");
        _;
    }

    modifier requirePaidAirline() {
        require(airlines[msg.sender].feePaid, "To participate you must pay");
        _;
    }

    modifier requireAirlineOperable(address airline) {
        require(airlines[airline].feePaid && airlines[airline].accepted, "Airline isn't operable");
    }

    modifier requireAuthorized() {
        require(authorizedCallers[msg.sender], "You don't have authorization");
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
        bytes32 key = getFlightKey(flightCode, departureTimestamp, airlineAddress);
        require(flightKeyToId[key] == 0, "The flight has already been created!");
        _;
    }

    modifier requireFlight(bytes32 key) {
        require(flights[keys].id > 0, "Flight must exist");
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


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    function setAuthorizedCaller(address caller) external requireContractOwner {
        authorizedCallers[caller] = true;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(address airline) external requireIsOperational requireBeAnAirline requireAcceptedAirline requirePaidAirline{
        _registerAirline(airline);
    }

    function _registerAirline(address airline) internal {
        Airline newAirline = Airline(airLineCount, false, airLineCount <= 4);
        newAirline.votes.push(airlines[msg.sender].id);
        airLineCount++;
        airlines[airline] = newAirline;

        emit AirlineAdded(newAirline.id, airline);
    }

    function registerFlight(string memory flightCode, uint departureTime, address airline) external requireIsOperational requireAuthorized requireAirlineOperable(airline) {
        bytes32 key = getFlightKey(airline, flightCode, departureTime);
        require(flights[keys].id == 0, "must be a new Flight");

        Flight newFlight = Flight(flightCount, key, airline, flightCode, departureTime, flightStatusDefault, departureTime);
        flights[key] = newFlight;
        flightCount++;

        airlinesFlights[airline].push(newFlight.id);

        emit FlightAdded(newFlight.id, newFlight.airline, newFlight.flightCode);
    }

    function setFlightCode(bytes32 key, uint status, uint updateTime) external requireIsOperational requireAuthorized requireFlight(key) {
        flights[key].status = status;
        flights[key].updateTime = updateTime;

        emit FlightCodeChanged(key, status);
    }

    function getFlight(string memory flightCode, uint departureTime, address airline) external view requireIsOperational requireAuthorized  returns (bytes32 key, address airlineAddress, string memory flightCode, uint departureStatusCode, uint departureTimestamp, uint updatedTimestamp){
        bytes32 key = getFlightKey(airline, flightCode, departureTime);
        Flight memory flight = flights[key];
        return (flight.key, flight.airline, flight.flightCode, flight.status,  flight.departureTime, flight.updateTime);
    }

    function getFlight(bytes32 key) external view external view requireIsOperational requireAuthorized  returns (bytes32 key, address airlineAddress, string memory flightCode, uint departureStatusCode, uint departureTimestamp, uint updatedTimestamp){
        Flight memory flight = flights[key];
        return (flight.key, flight.airline, flight.flightCode, flight.status,  flight.departureTime, flight.updateTime);
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy() external payable {

    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees() external pure {
    }


    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay() external pure {
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund() public payable requireIsOperational requireBeAnAirline {
        require(msg.value >= 10 ether, "You didn't pay enough");
        airlines[msg.sender].feePaid = true;
        emit AirlinePaidFund(msg.sender, msg.value);
    }

    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns (bytes32){
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    function voteAirline(address airline) public requireIsOperational requireBeAnAirline requireAcceptedAirline requirePaidAirline didntVote(airline) {
        airlines[airline].votes.push(airlines[msg.sender].id);
        airlines[airline].accepted = airlines[airline].votes.length > minToAccept;

        emit AirlineVote(airline, msg.sender);
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() external payable {
        fund();
    }


}

