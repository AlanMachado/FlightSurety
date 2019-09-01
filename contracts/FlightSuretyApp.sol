pragma solidity ^0.5.8;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./FlightSuretyData.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/
    FlightSuretyData flightData;
    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    // Account used to deploy contract
    address private contractOwner;

    enum Multiplier {
        noPAYER, simple, plus
    }

    uint private constant minToAccept = 5;
    uint private constant fundCost = 10 ether;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }

    mapping(bytes32 => Flight) private flights;


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
        // Modify to call data contract's status
        require(isOperational(), "Contract is currently not operational");
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

    modifier requireAirlineRegistered() {
        require(flightData.isAirlineRegistered(msg.sender), "Caller is not a registered airline");
        _;
    }

    modifier requireAirlineFunded() {
        require(flightData.isAirlineFunded(msg.sender), "Caller is not a funded airline");
        _;
    }

    modifier requireAirlineAccepted() {
        require(flightData.isAirlineAccepted(msg.sender), "Caller is not a accepted airline");
        _;
    }

    modifier fundedEnough() {
        require(msg.value >= fundCost, "Insufficient funding");
        _;
    }

    modifier sendChange() {
        _;
        uint amountToReturn = msg.value - 10 ether;
        if(amountToReturn > 0){
            msg.sender.transfer(amountToReturn);
        }
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor(address payable dataContract) public {
        contractOwner = msg.sender;
        flightData = FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns (bool){
        return flightData.isOperational();
        // Modify to call data contract's status
    }

    function setOperational(bool op) public requireContractOwner {
        flightData.setOperatingStatus(op);
    }

    function isAirlineRegistered(address airline) public view returns (bool) {
        require(airline != address(0), "airline must be a valid address.");
        return flightData.isAirlineRegistered(airline);
    }

    function isAirlineAccepted(address airline) public view returns (bool) {
        require(airline != address(0), "airline must be a valid address.");
        return flightData.isAirlineAccepted(airline);
    }

    function isAirlineFunded(address airline) public view returns (bool) {
        require(airline != address(0), "airline must be a valid address.");
        return flightData.isAirlineFunded(airline);
    }

    function isPassengerInsured(address passenger, address airline, string memory flightCode, uint departureTime) public view returns (bool) {
        require(isAirlineAccepted(airline), "airline not even accepted");
        require(isFlightRegistered(airline, flightCode, departureTime), "Flight isn't registered");
        return flightData.isPassengerInsured(passenger, airline, flightCode, departureTime);
    }

    function isFlightRegistered(address airline, string memory flightCode, uint departureTime) public view returns (bool) {
        require(isAirlineAccepted(airline), "airline not even accepted");
        return flightData.isFlightRegistered(airline, flightCode, departureTime);
    }

    function defineInsuranceMultiplier(uint value) internal pure returns (uint multi){
        if (value <= uint(Multiplier.simple)) {
            multi = uint(Multiplier.simple);
        } else if( value <= uint(Multiplier.plus)) {
            multi = uint(Multiplier.plus);
        }

        return multi;

    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/


    /**
     * @dev Add an airline to the registration queue
     *
     */
    function registerAirline(address newAirline) external requireIsOperational requireAirlineRegistered requireAirlineFunded requireAirlineAccepted returns (bool success){
        bool registered = isAirlineRegistered(newAirline);
        bool accepted = isAirlineAccepted(newAirline);
        if (registered && !accepted) {
            flightData.voteAirline(newAirline, msg.sender, minToAccept);
        } else if(!registered){
            flightData.registerAirline(newAirline, msg.sender);
        }
        return isAirlineRegistered(newAirline);
    }

    function fundAirline() external payable requireIsOperational requireAirlineRegistered fundedEnough sendChange returns (bool success){
        require(!isAirlineFunded(msg.sender), "Airline already funded");
        flightData.fund.value(fundCost)(msg.sender);
        return isAirlineFunded(msg.sender);
    }

    function registerFlight(string memory flightCode, uint departureTime) public requireAirlineFunded requireAirlineRegistered {
        flightData.registerFlight(msg.sender, flightCode, departureTime);
    }

    function InsureFlight(address airline, string memory flight, uint departureTime) public payable {
        bytes32 key = getFlightKey(airline, flight, departureTime);
        flightData.buyInsurance.value(msg.value)(key, msg.sender);
    }

    function processFlightStatus(address airline, string memory flightCode, uint256 departureTime, uint8 statusCode) internal requireIsOperational {
        if (statusCode == STATUS_CODE_LATE_AIRLINE) {

            bytes32 key = getFlightKey(airline, flightCode, departureTime);
            uint[] memory _insurances = flightData.getInsurancesFromFlight(key);
            uint multi = uint(Multiplier.noPAYER);

            for (uint i = 0; i < _insurances.length; i++) {
                (, uint amountPaid,) = flightData.getInsurance(_insurances[i]);
                multi = defineInsuranceMultiplier(amountPaid);
                flightData.creditInsurees(_insurances[i], multi);
            }
        }
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(address airline, string calldata flight, uint256 timestamp) external {
        uint8 index = getRandomIndex(msg.sender);

        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
            requester : msg.sender,
            isOpen : true});

        emit OracleRequest(index, airline, flight, timestamp);
    }

    function withdrawCredits() public requireIsOperational {
        flightData.pay(msg.sender);
    }


    // region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle() external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
            isRegistered : true,
            indexes : indexes
            });
    }

    function getMyIndexes() view external returns (uint8[3] memory){
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(uint8 index, address airline, string calldata flight, uint256 timestamp, uint8 statusCode) external {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }


    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns (bytes32){
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns (uint8[3] memory){
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8){
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;
            // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }
    // endregion
}   
