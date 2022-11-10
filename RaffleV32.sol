// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "../dependencies/VRFCoordinatorV2Interface.sol";
import "../dependencies/VRFConsumerBaseV2.sol";
import "../dependencies/AutomationCompatible.sol";
import {YieldAggregatorV32} from "./YieldAggregatorV32.sol";

//////// Custom Errors ////////
error RaffleV32__UpkeepNotNeeded(
    uint256 timePassed,
    uint256 numPlayers,
    uint256 raffleState
);
error RaffleV32__SendMoreToEnterRaffle();
error RaffleV32__RaffleNotOpen();
error RaffleV32__RaffleIsCalculating();

contract RaffleV32 is
    YieldAggregatorV32,
    AutomationCompatibleInterface,
    VRFConsumerBaseV2
{
    /**@title A modern type raffle
     * @author Ferris Vermeulen
     * @notice This project was built to test the implementation of the Chainlink VRF, Chainlink Keepers and Aave lending contracts.
     * @notice The Chainlink VRF provides verifiable randomness to ensure random winners.
     * @notice The Chainlink Keepers provides an automated trigger to end the lottery.
     * @notice Aave lending pools return yield on deposited collateral.
     * @notice This contract allows for withdrawls of the entry fee, making it a no loss on investment play (besides gas fees).
     */
    //////// Variables ////////
    enum RaffleState {
        OPEN,
        CALCULATING,
        PAUSED
    }
    //////// Chainlink VRF Variables ////////
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    //////// Lottery Variables ////////
    uint256 public immutable i_interval;
    uint256 public s_lastTimeStamp;
    uint256 private i_entranceFee;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    //////// Events ////////
    event RequestedRaffleWinner();
    event WinnerPicked(address indexed player, uint256 prize);

    ////// Main functions ////////
    constructor(
        address vrfCoordinatorV2,
        address _provider,
        address payable _weth,
        uint64 subscriptionId,
        bytes32 gasLane,
        uint256 interval,
        uint256 entranceFee,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) YieldAggregatorV32(_provider, _weth) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_entranceFee = entranceFee;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_callbackGasLimit = callbackGasLimit;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert RaffleV32__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert RaffleV32__RaffleNotOpen();
        }
        enterPlayer(msg.value);
    }

    // This is the function that the Chainlink Keeper nodes call to check whether they have to execute "performUpkeep".
    // The function check if `upkeepNeeded` returns True.
    // `upkeepNeeded` returns True when:
    // - The raffle is open.
    // - The time interval has passed.
    // - The raffle has players.
    // 'checkData' and 'performData' are optional input parameters.
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = getNumberOfPlayers() > 0;
        upkeepNeeded = (timePassed && isOpen && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // This is the function the Keepers node calls when `upkeepNeeded` returns True.
    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert RaffleV32__UpkeepNotNeeded(
                (block.timestamp - s_lastTimeStamp),
                getNumberOfPlayers(),
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        // We let the Keepers node call the VRF request random words(numbers)
        // Upon this request the VRF will call the function 'fulfillRandomWords'
        i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner();
    }

    /**
     * @dev This is the function that Chainlink VRF node
     * calls to send the money to the random winner.
     */
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        // s_players size 10
        // randomNumber 202
        // 202 % 10 ? what's doesn't divide evenly into 202?
        // 20 * 10 = 200
        // 2
        // 202 % 10 = 2
        uint256 indexOfWinner = randomWords[0] % getNumberOfPlayers();
        address recentWinner = getAddressAtIndex(indexOfWinner);
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        uint256 prize = getYieldBalance();
        s_addressToAmountPrizes[recentWinner] += prize;
        emit WinnerPicked(recentWinner, prize);
    }

    // In this example contract the state can be altered by any address to pause/unpause the raffle.
    // This way the Keepers node won't continuously trigger the contract to send transactions and waste tokens.
    // Whenever any person would like to try out the contract, unpause the contract with the function below.
    function togglePause() public returns (RaffleState) {
        if (s_raffleState == RaffleState.OPEN) {
            s_raffleState = RaffleState.PAUSED;
        } else if (s_raffleState == RaffleState.PAUSED) {
            s_raffleState = RaffleState.OPEN;
        } else {
            revert RaffleV32__RaffleIsCalculating();
        }
        return s_raffleState;
    }

    // The raffle could get stuck in the calculating state if the Keepers contract triggers an underfunded VRF subscription, causing the VRF transaction to fail.
    // The Keepers contract won't be able to perform upkeep unless the state is open.
    // This function is to manually reset the state to open.
    function restartRaffle() public {
        s_raffleState = RaffleState.OPEN;
    }


    //////// view functions /////////
    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }
}
