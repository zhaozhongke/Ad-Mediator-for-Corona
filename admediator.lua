------------------------------------------------------------
------------------------------------------------------------
-- Ad Mediator for Corona
--
-- Ad network mediation module for Ansca Corona
-- by Deniz Aydinoglu
--
-- he2apps.com
--
-- GitHub repository and documentation:
-- https://github.com/deniza/Ad-Mediator-for-Corona
------------------------------------------------------------
------------------------------------------------------------

local json = require("json")

AdMediator = {
    clientIPAddress = "",
}

local networks = {}
local weightTable = {}
local networksByPriority = {}
local adRequestDelay = nil
local currentNetworkIdx = nil
local currentImageUrl = nil
local currentAdUrl = nil
local currentBanner = nil
local loadingBeacon = false
local isHidden = false
local enableWebView = false
local webPopupVisible = false
local currentWebPopupContent
local adDisplayGroup = display.newGroup()
local adPosX = 0
local adPosY = 0
local animationEnabled = false
local animationTargetX
local animationTargetY
local animationDuration
local timerHandle = nil

local userAgentIOS = "Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_2 like Mac OS X; en) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8F190 Safari/6533.18.5"
local userAgentAndroid = "Mozilla/5.0 (Linux; U; Android 2.2; en-us; Nexus One Build/FRF91) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1"
local userAgentString
local PLATFORM_IOS, PLATFORM_ANDROID = 0, 1
local platform
local runningOnIPAD

local function findClientIPAddress()

    local function ipListener(event)
        if not event.isError and event.response ~= "" then
            AdMediator.clientIPAddress = event.response
        end
    end
    
    network.request("http://whatismyip.org","GET",ipListener)

end


local function cleanPreviousLoadFailStatus()
    for i=1,#networks do
        networks[i].failedToLoad = false
    end
end

local function fetchNextNetworkBasedOnPriority()
    
    if isHidden then
        return
    end
    
    for _,network in pairs(networksByPriority) do
        if not network.failedToLoad then
            currentNetworkIdx = network.idx
            network:requestAd()
            --print("requesting ad:",network.name)
            break
        end        
    end
    
end

local function fetchRandomNetwork()

    local random = math.floor(math.random()*100) + 1
    for i=1,#weightTable do        
        if random >= weightTable[i].min and random <= weightTable[i].max then
            currentNetworkIdx = i
            break
        end
    end
    
    networks[currentNetworkIdx]:requestAd()    
    --print("requesting ad:",networks[currentNetworkIdx].name)

end

local function displayContentInWebPopup(x,y,width,height,contentHtml)
        
    local filename = "webview.html"
    local path = system.pathForFile( filename, system.TemporaryDirectory )
    local fhandle = io.open(path,"w")
    -- Default for iPhone/iTouch
    local meta = "<meta name=\"viewport\" content=\"width=320; user-scalable=0;\"/>"
    
    local newX = x
    local newY = y
    local newWidth = 320
    local newHeight = 50
    local scale = 1/display.contentScaleY
 
    -- disable any existing viewport meta tag definition
    contentHtml = string.gsub(contentHtml, '<meta name="viewport"', '<meta name="disabled_viewport"')

    if platform == PLATFORM_ANDROID then

        meta = "<meta name=\"viewport\" content=\"width=320; initial-scale=1; minimum-scale=1; maximum-scale=2; user-scalable=0;\"/>"
        -- Max scale for android is 2 (enforced above just in case), so adjust web popup if over 2. 
        if scale > 2 then scale = scale/2
                newWidth = (width/scale) + 1
                newHeight = (height/scale) + 2
                newX = x + (width - newWidth)/2
                newY = y + (height - newHeight)/2
        end
            
    elseif runningOnIPAD then
        meta = "<meta name=\"viewport\" content=\"width=320; initial-scale=" .. scale .. 
                                                          "; minimum-scale=" .. scale ..
                                                          "; maximum-scale=" .. scale .. "; user-scalable=0;\"/>"
    end
 
    local bodyStyle = "<body style=\"margin:0; padding:0;\">"
    fhandle:write("<html><head>"..meta.."</head>"..bodyStyle..contentHtml.."</body></html>")
    io.close(fhandle)
    
    local function webPopupListener( event )            
        if string.find(event.url, "file://", 1, false) == 1 then
            return true
        else
            system.openURL(event.url)
        end
    end
    
    local options = { hasBackground=false, baseUrl=system.TemporaryDirectory, urlRequest=webPopupListener } 
    native.showWebPopup( newX, newY, newWidth, newHeight, filename.."?"..os.time(), options)
        
    webPopupVisible = true
    currentWebPopupContent = contentHtml
 
end

local function hideCurrentBannerWithAnimation(onCompleteFunc)
    transition.to(adDisplayGroup,{time=animationDuration/2,x=animationTargetX,y=animationTargetY,onComplete=function()
            if currentBanner then
                currentBanner:removeSelf()
                currentBanner = nil
            end
            onCompleteFunc()
        end})
end

local function adImageDownloadListener(event)
    
    if not event.isError then
    
        local function showNewBanner(newBanner)
            if currentBanner then
                currentBanner:removeSelf()
            end
            currentBanner = newBanner
            currentBanner.isVisible = true
            adDisplayGroup:insert(currentBanner)            
        end
            
        if loadingBeacon then
        
            event.target:removeSelf()
            loadingBeacon = false
            
        else
        
            if animationEnabled then
                
                if currentBanner then
                
                    event.target.isVisible = false
                
                    hideCurrentBannerWithAnimation(function()
                            showNewBanner(event.target)
                            transition.to(adDisplayGroup,{time=animationDuration/2,x=adPosX,y=adPosY})
                        end)
                        
                else
                    adDisplayGroup.x = animationTargetX
                    adDisplayGroup.y = animationTargetY
                    showNewBanner(event.target)
                    
                    transition.to(adDisplayGroup,{time=animationDuration/2,x=adPosX,y=adPosY})
                end
                
            else                
                showNewBanner(event.target)
            end
        end
        
        cleanPreviousLoadFailStatus()
        
        --print("image loaded")
    
    else
        --print("image download error!")
    end        
    
end

local function adResponseCallback(event)
    
    local webPopupOpened = false
    
    if event.available then
        
        currentImageUrl = event.imageUrl
        currentAdUrl = event.adUrl
        
        if event.beacon then
            loadingBeacon = true
        else
            loadingBeacon = false
        end
        
        if event.htmlContent then
            
            if animationEnabled and currentBanner then            
                hideCurrentBannerWithAnimation(function()
                        if not isHidden then
                            displayContentInWebPopup(adPosX, adPosY, 320, 50, event.htmlContent)
                        else
                            currentWebPopupContent = event.htmlContent
                        end
                    end)
            else
                if not isHidden then
                    displayContentInWebPopup(adPosX, adPosY, 320, 50, event.htmlContent)
                else
                    currentWebPopupContent = event.htmlContent
                end
            end
            
            networks[currentNetworkIdx].usesWebPopup = true
            
        else
        
            if enableWebView then
            
                local meta = "<meta name=\"viewport\" content=\"width=320; user-scalable=0;\"/>"
                local bodyStyle = "<body style=\"margin:0; padding:0;\">"
                local contentHtml = "<html><head>"..meta.."</head>"..bodyStyle.."<a href='"..currentAdUrl.."'><img src='"..currentImageUrl.."'/></a></body></html>"
                
                if animationEnabled and currentBanner then        
                    hideCurrentBannerWithAnimation(function()
                            if not isHidden then
                                displayContentInWebPopup(adPosX, adPosY, 320, 50, contentHtml)
                            else
                                currentWebPopupContent = contentHtml
                            end
                        end)
                else
                    if not isHidden then
                        displayContentInWebPopup(adPosX, adPosY, 320, 50, contentHtml)
                    else
                        currentWebPopupContent = event.contentHtml
                    end
                end
                
                networks[currentNetworkIdx].usesWebPopup = true
            
            else
                
                if webPopupVisible then
                    native.cancelWebPopup()
                    webPopupVisible = false
                end
                
                display.loadRemoteImage(currentImageUrl, "GET", adImageDownloadListener, "admediator_tmp_adimage_"..os.time(), system.TemporaryDirectory)
                
                networks[currentNetworkIdx].usesWebPopup = false
                
            end
            
        end
        
    else
    
        --print("network failed:",networks[currentNetworkIdx].name)
        networks[currentNetworkIdx].failedToLoad = true
        
        fetchNextNetworkBasedOnPriority()
    end
    
end

function AdMediator.init(posx,posy,adReqDelay)

    adRequestDelay = adReqDelay
    adDisplayGroup:addEventListener("tap",function() system.openURL(currentAdUrl) return true end)        
    
    AdMediator.setPosition(posx,posy)
    
    print(system.getInfo("platformName"))
    print(system.getInfo("model"))
    
    if system.getInfo("platformName") == "Android" then
        userAgentString = userAgentAndroid
        platform = PLATFORM_ANDROID
    else
        userAgentString = userAgentIOS
        platform = PLATFORM_IOS
        
        if system.getInfo( "model" ) == "iPad" or system.getInfo( "model" ) == "iPad Simulator" then
            runningOnIPAD = true
        else
            runningOnIPAD = false
        end
    end
    
    Runtime:addEventListener("adMediator_adResponse",adResponseCallback)
    
end

function AdMediator.initFromUrl(initUrl, initCallbackFunction)

    local function initRequestListener(event)
    
        if event.isError then
            initCallbackFunction(false)
            return
        end
        
        local config = json.decode(event.response)
        
        if config.animation.enabled then
            animationEnabled = true
            animationTargetX = config.animation.targetx
            animationTargetY = config.animation.targety
            animationDuration = config.animation.duration
        end
        
        config.x = config.x or adPosX
        config.y = config.y or adPosY
        
        AdMediator.init(config.x,config.y,config.adDelay)
        AdMediator.useWebView(config.useWebView)
        
        if config.xscale and config.yscale then
            AdMediator.setScale(config.xscale, config.yscale)
        end
        
        for _,networkDef in ipairs(config.networks) do
            AdMediator.addNetwork( networkDef )
        end
        
        initCallbackFunction(true)
    end
    
    network.request(initUrl, "GET", initRequestListener)

end

function AdMediator.show()

    isHidden = false
    adDisplayGroup.isVisible = true
    adDisplayGroup:toFront()
    
    if networks[currentNetworkIdx].usesWebPopup and currentWebPopupContent then
        displayContentInWebPopup(adPosX, adPosY, 320, 50, currentWebPopupContent)
    end

    if timerHandle then
        timer.resume(timerHandle)
    end
    
    return true
    
end

function AdMediator.hide()

    isHidden = true
    adDisplayGroup.isVisible = false
    if webPopupVisible then
        native.cancelWebPopup()
        webPopupVisible = false
    end
    
    if timerHandle then
        timer.pause(timerHandle)
    end
    
    return true
    
end

function AdMediator.useAnimation(targetx,targety,duration)

    animationEnabled = true
    animationTargetX = targetx
    animationTargetY = targety
    animationDuration = duration

end

function AdMediator.setScale(scalex,scaley)
    adDisplayGroup:scale(scalex,scaley)
end

function AdMediator.useWebView(useFlag)
    enableWebView = useFlag
end

function AdMediator.setPosition(x,y)
    adPosX = x
    adPosY = y
    adDisplayGroup.x = adPosX
    adDisplayGroup.y = adPosY    
end

function AdMediator.getUserAgentString()
    return userAgentString
end


function AdMediator.addNetwork(params)

    if params.enabled == nil then
        params.enabled = true
    elseif params.enabled == false then
        return
    end
    
    local networkObject = require(params.name)
    networks[#networks+1] = networkObject
    networkObject.priority = params.backfillpriority
    networkObject.weight = params.weight
    networkObject.name = params.name
    networkObject.idx = #networks    
    
    networkObject:init(params.networkParams)
    
    print("addNetwork:",params.name,params.weight,params.backfillpriority)
    
end

function AdMediator.start()

    local totalWeight = 0    
    for _,network in ipairs(networks) do
        networksByPriority[#networksByPriority+1] = network
        totalWeight = totalWeight + network.weight
    end    
    table.sort(networksByPriority, function(a,b) return a.priority<b.priority end)
    
    if totalWeight < 100 then
        local delta = 100 - totalWeight
        local added = 0
        for _,network in ipairs(networks) do
            local toadd = math.floor(delta * network.weight/totalWeight)
            added = added + toadd 
            network.weight = network.weight + toadd
        end
        networks[1].weight = networks[1].weight + delta - added 
    end
    
    local currentMaxWeight = 0
    for _,network in ipairs(networks) do
        local weightRecord = {min=currentMaxWeight+1,max=currentMaxWeight+network.weight}
        currentMaxWeight = currentMaxWeight + network.weight
        weightTable[#weightTable+1] = weightRecord
        
        print("weight",_,network.weight)
    end
    
    fetchRandomNetwork()
    timerHandle = timer.performWithDelay( adRequestDelay * 1000, fetchRandomNetwork, 0 )
    
    return true

end

findClientIPAddress()
