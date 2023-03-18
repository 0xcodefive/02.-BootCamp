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
}

contract CryptoGochiGame is ReentrancyGuard, VRFConsumerBaseV2, ConfirmedOwner {
    using SafeMath for uint8;
    using SafeMath for uint256;

    ICryptoGochiToken gochiToken;
    address public gochiTokenAddress;
    
    uint256 public limitForFreeMint;
    uint256 public restrictionTimer;
    uint256 public morphMul;
    uint256 public priceToBirth;   
    uint256 private constant st = 100;

    VRFCoordinatorV2Interface COORDINATOR;
    uint16 internal requestConfirmations = 2;
    uint32 internal callbackGasLimit = 200000;
    uint32 internal numWords = 1;
    uint64 internal s_subscriptionId = 2714;
    address internal constant vrfCoordinator = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 internal constant keyHash = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    struct Gochi {
        uint8 level;
        uint8 epoch;
        uint256 feeded;
        uint256 satisfaction;
        uint256 education;
        uint256 restrictionOnFeeded;
        uint256 restrictionOnSatisfaction;
        uint256 restrictionOnEducation;
        uint256 restrictionOnSleep;
        address owner;
        address nanny;
    }
    Gochi[] gochies;

    mapping(address => bool) public hasFreeGochi;
    mapping(address => uint256) public gochiCountFromAddress;

    event NewGochiWasBorn(address indexed owner, uint256 index);

    modifier onlyGochiOwner(uint256 index) {
        require(msg.sender == gochies[index].owner, "Only Gochi owner can call this function");
        _;
    }

    modifier onlyGochiNanny(uint256 index) {
        require(msg.sender == gochies[index].nanny, "Only Gochi owner or nanny can call this function");
        _;
    }

    constructor()
    VRFConsumerBaseV2(vrfCoordinator)
    ConfirmedOwner(msg.sender)
    payable {
        COORDINATOR = VRFCoordinatorV2Interface(
            vrfCoordinator
        );
        restrictionTimer = 20; // 1 minute
        morphMul = 10;
        priceToBirth = 10 * 10**18;
        limitForFreeMint = 10;
        _birthGochi(address(this));
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
    
    function setPriceToBirth (uint32 _newLimit) onlyOwner {
        limitForFreeMint = _newLimit;
    }

    function freeBirthGochi(address _to) public {
        require(gochies.length <= limitForFreeMint && !hasFreeGochi(_to), "Free birth is not available for you");
        _birthGochi(_to);
    }

    function birthGochi(address _to) public {
        IERC20Metadata(gochiTokenAddress)._burn(msg.sender, priceToBirth);
        _birthGochi(_to);
    }

    function _birthGochi(address _to) private {
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
        gochiCountFromAddress[_to]++;
        emit NewGochiWasBorn(_to, gochies.length - 1);
    }

    function setNannyForGochi(address _to, uint256 _index) public onlyGochiOwner(_index) {
        gochies[index].nanny = _to;
    }

    function getGochiesByOwner(address _owner) public returns(Gochies[]) {
        Gochies[] thisGochies;
        for (uint256 i; i < gochies.lenght; i++){
            if (gochies[i].owner == _owner){
                thisGochies.push(gochies[i]);
            }
            if (thisGochies.lenght == gochiCountFromAddress[_owner]) {
                return thisGochies;
            }
        }
        return thisGochies;
    }

    function transferGochiOwner(address _to, uint256 _index) public onlyGochiOwner(_index) {
        gochiCountFromAddress[gochies[index].owner]--;
        gochies[index].owner = _to;
        gochiCountFromAddress[_to]++;
    }

    function getGochiFeededByPercent(uint256 _index) public view retuns(uint256){
        uint256 max = gochies[index].level.mul(10).add(st);
        uint256 ths = _getGochiFeeded(_index);
        return max > ths ? ths.mul(100).div(max) : 100;
    }

    function _getGochiFeeded(uint256 _index) private view retuns(uint256){
        uint256 proto = gochies[index].feeded.add(10);
        uint256 minus = block.timestamp.sub(gochies[index].restrictionOnFeeded).div(restrictionTimer);
        return proto > minus ? proto.sub(minus) : 10;
    }

    function feedGochi(uint256 _index) public onlyGochiNanny(_index) {
        require(gochies[index].restrictionOnSleep >= block.timestamp, "Gochi is sleeping");
        require(gochies[index].restrictionOnFeeded >= block.timestamp, "Gochi is very well fed");
        uint256 max = gochies[index].level.mul(10).add(st);
        uint256 ths = _getGochiFeeded(_index);
        gochies[index].feeded = ths < max ? ths : max;
        gochies[index].restrictionOnFeeded = block.timestamp.add(restrictionTimer);
    }

    function getGochiSatisfactionByPercent(uint256 _index) public view retuns(uint256){
        uint256 max = gochies[index].level.mul(10).add(st);
        uint256 ths = _getGochiSatisfaction(_index);
        return max > ths ? ths.mul(100).div(max) : 100;
    }

    function _getGochiSatisfaction(uint256 _index) private view retuns(uint256){
        uint256 proto = gochies[index].satisfaction.add(10);
        uint256 minus = block.timestamp.sub(gochies[index].restrictionOnSatisfaction).div(restrictionTimer);
        return proto > minus ? proto.sub(minus) : 10;
    }

    function satisfyGochi(uint256 _index) public onlyGochiNanny(_index) {
        require(gochies[index].restrictionOnSleep >= block.timestamp, "Gochi is sleeping");
        require(gochies[index].restrictionOnSatisfaction >= block.timestamp, "Gochi is very well satisfied");
        uint256 max = gochies[index].level.mul(10).add(st);
        uint256 ths = _getGochiSatisfaction(_index);
        gochies[index].satisfaction = ths < max ? ths : max;
        gochies[index].restrictionOnSatisfaction = block.timestamp.add(restrictionTimer);
    }

    function getGochiEducationByPercent(uint256 _index) public view retuns(uint256){
        uint256 max = gochies[index].level.mul(10).add(st);
        uint256 ths = _getGochiEducation(_index);
        return max > ths ? ths.mul(100).div(max) : 100;
    }

    function _getGochiEducation(uint256 _index) private view retuns(uint256){
        uint256 proto = gochies[index].education.add(10);
        uint256 minus = block.timestamp.sub(gochies[index].restrictionOnEducation).div(restrictionTimer);
        return proto > minus ? proto.sub(minus) : 10;
    }

    function educateGochi(uint256 _index) public onlyGochiNanny(_index) {
        require(gochies[index].restrictionOnSleep >= block.timestamp, "Gochi is sleeping");
        require(gochies[index].restrictionOnEducation >= block.timestamp, "Gochi is very well educated");
        uint256 max = gochies[index].level.mul(10).add(st);
        uint256 ths = _getGochiEducation(_index);
        gochies[index].education = ths < max ? ths : max;
        gochies[index].restrictionOnEducation = block.timestamp.add(restrictionTimer);
    }

    function gochiMorph(uint256 _index) public onlyGochiOwner(_index) {
        require(_getGochiFeeded(_index) >= 85, "Not fed enough, need more then 85%");
        require(_getGochiSatisfaction(_index) >= 85, "Not satisfied enough, need more then 85%");
        require(_getGochiEducation(_index) >= 85, "Not educated enough, need more then 85%");

    }
}