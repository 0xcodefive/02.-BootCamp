// SPDX-License-Identifier: MIT
/************************************************************\
*                                                            *
*      ██████╗ ██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗     *
*     ██╔═████╗╚██╗██╔╝██╔════╝██╔═████╗██╔══██╗██╔════╝     *
*     ██║██╔██║ ╚███╔╝ ██║     ██║██╔██║██║  ██║█████╗       *
*     ████╔╝██║ ██╔██╗ ██║     ████╔╝██║██║  ██║██╔══╝       *
*     ╚██████╔╝██╔╝ ██╗╚██████╗╚██████╔╝██████╔╝███████╗     *
*      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝     *
*                                                            *
\************************************************************/                                                  

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface ICryptoGochiToken {
    function mint(address _to, uint256 _amount)external;
    function burn(address _from, uint256 _amount)external;
}

contract CryptoGochiGame is ReentrancyGuard, VRFConsumerBaseV2, ConfirmedOwner {
    using SafeMath for uint8;
    using SafeMath for uint16;
    using SafeMath for uint256;

    ICryptoGochiToken gochiToken;
    address public gochiTokenAddress;
    uint256 priceToBirth;

    VRFCoordinatorV2Interface COORDINATOR;

    uint16 internal requestConfirmations = 2;
    uint32 internal callbackGasLimit = 200000;
    uint32 internal numWords = 1;
    uint64 internal s_subscriptionId = 2714;
    address internal constant vrfCoordinator = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 internal constant keyHash = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    uint256 public restrictionTimer;

    struct Gochi {
        uint8 level;
        uint8 epoch;
        uint16 feeded;
        uint16 satisfaction;
        uint16 education;
        uint256 restrictionOnFeeded;
        uint256 restrictionOnSatisfaction;
        uint256 restrictionOnEducation;
        uint256 restrictionOnSleep;
        address owner;
        address nanny;
    }
    Gochi[] gochies;

    event NewGochiWasBorn(address indexed owner, uint256 index);

    constructor()
    VRFConsumerBaseV2(vrfCoordinator)
    ConfirmedOwner(msg.sender)
    payable {
        COORDINATOR = VRFCoordinatorV2Interface(
            vrfCoordinator
        );
        restrictionTimer = 20; // 1 minute
        priceToBirth = 10 * 10**18;
    }

    function setRestrictionTimer (uint256 _timer) onlyOwner {
        restrictionTimer = _timer;
    }

    function setGchiTokenAddress (address _newAddress) onlyOwner {
        gochiTokenAddress = _newAddress;
        gochiToken = ICryptoGochiToken(gochiTokenAddress);
    }

    function setPriceToBirth (uint256 _newPrice) onlyOwner {
        priceToBirth = _newPrice;
    }

    function birthGochi(address _to) internal {
        gochiToken.burn(_to, priceToBirth);
        gochies.push(Gochi({
            level: 0,
            epoch: 0,
            feeded: 0,
            satisfaction: 0,
            education: 0,
            restrictionOnFeeded: 0,
            restrictionOnSatisfaction: 0,
            restrictionOnEducation: 0,
            restrictionOnSleep: 0,
            owner: _to,
            nanny: _to
        }));
        emit NewGochiWasBorn(_to, gochies.length - 1);
    }
}