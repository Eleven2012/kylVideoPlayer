//
//  kylKYLPlayer.swift
//  kylVideoKYLPlayer
//
//  Created by yulu kong on 2019/8/10.
//  Copyright © 2019 yulu kong. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation
import CoreGraphics

// MARK: - types

/// Video fill mode options for `KYLPlayer.fillMode`.
///
/// - resize: Stretch to fill.
/// - resizeAspectFill: Preserve aspect ratio, filling bounds.
/// - resizeAspectFit: Preserve aspect ratio, fill within bounds.
public enum KYLPlayerFillMode {
    case resize
    case resizeAspectFill
    case resizeAspectFit // default
    
    public var avFoundationType: String {
        get {
            switch self {
            case .resize:
                return AVLayerVideoGravity.resize.rawValue
            case .resizeAspectFill:
                return AVLayerVideoGravity.resizeAspectFill.rawValue
            case .resizeAspectFit:
                return AVLayerVideoGravity.resizeAspect.rawValue
            }
        }
    }
}

/// Asset playback states.
public enum PlaybackState: Int, CustomStringConvertible {
    case stopped = 0
    case playing
    case paused
    case failed
    
    public var description: String {
        get {
            switch self {
            case .stopped:
                return "Stopped"
            case .playing:
                return "Playing"
            case .failed:
                return "Failed"
            case .paused:
                return "Paused"
            }
        }
    }
}

/// Asset buffering states.
public enum BufferingState: Int, CustomStringConvertible {
    case unknown = 0
    case ready
    case delayed
    
    public var description: String {
        get {
            switch self {
            case .unknown:
                return "Unknown"
            case .ready:
                return "Ready"
            case .delayed:
                return "Delayed"
            }
        }
    }
}

// MARK: - KYLPlayerDelegate

/// KYLPlayer delegate protocol
public protocol KYLPlayerDelegate: NSObjectProtocol {
    func KYLPlayerReady(_ KYLPlayer: KYLPlayer)
    func KYLPlayerPlaybackStateDidChange(_ KYLPlayer: KYLPlayer)
    func KYLPlayerBufferingStateDidChange(_ KYLPlayer: KYLPlayer)
    
    // This is the time in seconds that the video has been buffered.
    // If implementing a UIProgressView, user this value / KYLPlayer.maximumDuration to set progress.
    func KYLPlayerBufferTimeDidChange(_ bufferTime: Double)
}


/// KYLPlayer playback protocol
public protocol KYLPlayerPlaybackDelegate: NSObjectProtocol {
    func KYLPlayerCurrentTimeDidChange(_ KYLPlayer: KYLPlayer)
    func KYLPlayerPlaybackWillStartFromBeginning(_ KYLPlayer: KYLPlayer)
    func KYLPlayerPlaybackDidEnd(_ KYLPlayer: KYLPlayer)
    func KYLPlayerPlaybackWillLoop(_ KYLPlayer: KYLPlayer)
}

// MARK: - KYLPlayer

/// ▶️ KYLPlayer, simple way to play and stream media
open class KYLPlayer: UIViewController {
    
    /// KYLPlayer delegate.
    open weak var KYLPlayerDelegate: KYLPlayerDelegate?
    
    /// Playback delegate.
    open weak var playbackDelegate: KYLPlayerPlaybackDelegate?
    
    // configuration
    
    /// Local or remote URL for the file asset to be played.
    ///
    /// - Parameter url: URL of the asset.
    open var url: URL? {
        didSet {
            setup(url: url)
        }
    }
    
    /// Determines if the video should autoplay when a url is set
    ///
    /// - Parameter bool: defaults to true
    open var autoplay: Bool = true
    
    /// For setting up with AVAsset instead of URL
    /// Note: Resets URL (cannot set both)
    open var asset: AVAsset? {
        get { return _asset }
        set { _ = newValue.map { setupAsset($0) } }
    }
    
    /// Mutes audio playback when true.
    open var muted: Bool {
        get {
            return self._avKYLPlayer.isMuted
        }
        set {
            self._avKYLPlayer.isMuted = newValue
        }
    }
    
    /// Volume for the KYLPlayer, ranging from 0.0 to 1.0 on a linear scale.
    open var volume: Float {
        get {
            return self._avKYLPlayer.volume
        }
        set {
            self._avKYLPlayer.volume = newValue
        }
    }
    
    /// Specifies how the video is displayed within a KYLPlayer layer’s bounds.
    /// The default value is `AVLayerVideoGravityResizeAspect`. See `FillMode` enum.
    open var fillMode: String {
        get {
            return self._KYLPlayerView.fillMode
        }
        set {
            self._KYLPlayerView.fillMode = newValue
        }
    }
    
    /// Pauses playback automatically when resigning active.
    open var playbackPausesWhenResigningActive: Bool = true
    
    /// Pauses playback automatically when backgrounded.
    open var playbackPausesWhenBackgrounded: Bool = true
    
    /// Resumes playback when became active.
    open var playbackResumesWhenBecameActive: Bool = true
    
    /// Resumes playback when entering foreground.
    open var playbackResumesWhenEnteringForeground: Bool = true
    
    // state
    
    /// Playback automatically loops continuously when true.
    open var playbackLoops: Bool {
        get {
            return self._avKYLPlayer.actionAtItemEnd == .none
        }
        set {
            if newValue {
                self._avKYLPlayer.actionAtItemEnd = .none
            } else {
                self._avKYLPlayer.actionAtItemEnd = .pause
            }
        }
    }
    
    /// Playback freezes on last frame frame at end when true.
    open var playbackFreezesAtEnd: Bool = false
    
    /// Current playback state of the KYLPlayer.
    open var playbackState: PlaybackState = .stopped {
        didSet {
            if playbackState != oldValue || !playbackEdgeTriggered {
                self.KYLPlayerDelegate?.KYLPlayerPlaybackStateDidChange(self)
            }
        }
    }
    
    /// Current buffering state of the KYLPlayer.
    open var bufferingState: BufferingState = .unknown {
        didSet {
            if bufferingState != oldValue || !playbackEdgeTriggered {
                self.KYLPlayerDelegate?.KYLPlayerBufferingStateDidChange(self)
            }
        }
    }
    
    /// Playback buffering size in seconds.
    open var bufferSize: Double = 10
    
    /// Playback is not automatically triggered from state changes when true.
    open var playbackEdgeTriggered: Bool = true
    
    /// Maximum duration of playback.
    open var maximumDuration: TimeInterval {
        get {
            if let KYLPlayerItem = self._KYLPlayerItem {
                return CMTimeGetSeconds(KYLPlayerItem.duration)
            } else {
                return CMTimeGetSeconds(CMTime.indefinite)
            }
        }
    }
    
    /// Media playback's current time.
    open var currentTime: TimeInterval {
        get {
            if let KYLPlayerItem = self._KYLPlayerItem {
                return CMTimeGetSeconds(KYLPlayerItem.currentTime())
            } else {
                return CMTimeGetSeconds(CMTime.indefinite)
            }
        }
    }
    
    /// The natural dimensions of the media.
    open var naturalSize: CGSize {
        get {
            if let KYLPlayerItem = self._KYLPlayerItem,
                let track = KYLPlayerItem.asset.tracks(withMediaType: .video).first {
                
                let size = track.naturalSize.applying(track.preferredTransform)
                return CGSize(width: fabs(size.width), height: fabs(size.height))
            } else {
                return CGSize.zero
            }
        }
    }
    
    /// KYLPlayer view's initial background color.
    open var layerBackgroundColor: UIColor? {
        get {
            guard let backgroundColor = self._KYLPlayerView.playerLayer.backgroundColor
                else {
                    return nil
            }
            return UIColor(cgColor: backgroundColor)
        }
        set {
            self._KYLPlayerView.playerLayer.backgroundColor = newValue?.cgColor
        }
    }
    
    // MARK: - private instance vars
    
    internal var _asset: AVAsset? {
        didSet {
            if let _ = self._asset {
                //                self.setupKYLPlayerItem(nil)
            }
        }
    }
    internal var _avKYLPlayer: AVPlayer
    internal var _KYLPlayerItem: AVPlayerItem?
    internal var _timeObserver: Any?
    
    internal var _KYLPlayerView: KYLPlayerView = KYLPlayerView(frame: .zero)
    internal var _seekTimeRequested: CMTime?
    
    internal var _lastBufferTime: Double = 0
    
    //Boolean that determines if the user or calling coded has trigged autoplay manually.
    internal var _hasAutoplayActivated: Bool = true
    
    // MARK: - object lifecycle
    
    public convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self._avKYLPlayer = AVPlayer()
        self._avKYLPlayer.actionAtItemEnd = .pause
        self._timeObserver = nil
        
        super.init(coder: aDecoder)
    }
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        self._avKYLPlayer = AVPlayer()
        self._avKYLPlayer.actionAtItemEnd = .pause
        self._timeObserver = nil
        
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    deinit {
        self._avKYLPlayer.pause()
        self.setupKYLPlayerItem(nil)
        
        self.removeKYLPlayerObservers()
        
        self.KYLPlayerDelegate = nil
        self.removeApplicationObservers()
        
        self.playbackDelegate = nil
        self.removeKYLPlayerLayerObservers()
        self._KYLPlayerView.player = nil
    }
    
    // MARK: - view lifecycle
    
    open override func loadView() {
        self._KYLPlayerView.playerLayer.isHidden = true
        self.view = self._KYLPlayerView
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        if let url = url {
            setup(url: url)
        } else if let asset = asset {
            setupAsset(asset)
        }
        
        self.addKYLPlayerLayerObservers()
        self.addKYLPlayerObservers()
        self.addApplicationObservers()
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if self.playbackState == .playing {
            self.pause()
        }
    }
    
    // MARK: - Playback funcs
    
    /// Begins playback of the media from the beginning.
    open func playFromBeginning() {
        self.playbackDelegate?.KYLPlayerPlaybackWillStartFromBeginning(self)
        self._avKYLPlayer.seek(to: CMTime.zero)
        self.playFromCurrentTime()
    }
    
    /// Begins playback of the media from the current time.
    open func playFromCurrentTime() {
        if !autoplay {
            //external call to this method with auto play off.  activate it before calling play
            _hasAutoplayActivated = true
        }
        play()
    }
    
    fileprivate func play() {
        if autoplay || _hasAutoplayActivated {
            self.playbackState = .playing
            self._avKYLPlayer.play()
        }
    }
    
    /// Pauses playback of the media.
    open func pause() {
        if self.playbackState != .playing {
            return
        }
        
        self._avKYLPlayer.pause()
        self.playbackState = .paused
    }
    
    /// Stops playback of the media.
    open func stop() {
        if self.playbackState == .stopped {
            return
        }
        
        self._avKYLPlayer.pause()
        self.playbackState = .stopped
        self.playbackDelegate?.KYLPlayerPlaybackDidEnd(self)
    }
    
    /// Updates playback to the specified time.
    ///
    /// - Parameters:
    ///   - time: The time to switch to move the playback.
    ///   - completionHandler: Call block handler after seeking/
    open func seek(to time: CMTime, completionHandler: ((Bool) -> Swift.Void)? = nil) {
        if let KYLPlayerItem = self._KYLPlayerItem {
            return KYLPlayerItem.seek(to: time, completionHandler: completionHandler)
        } else {
            _seekTimeRequested = time
        }
    }
    
    /// Updates the playback time to the specified time bound.
    ///
    /// - Parameters:
    ///   - time: The time to switch to move the playback.
    ///   - toleranceBefore: The tolerance allowed before time.
    ///   - toleranceAfter: The tolerance allowed after time.
    ///   - completionHandler: call block handler after seeking
    open func seekToTime(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: ((Bool) -> Swift.Void)? = nil) {
        if let KYLPlayerItem = self._KYLPlayerItem {
            return KYLPlayerItem.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter, completionHandler: completionHandler)
        }
    }
    
    /// Captures a snapshot of the current KYLPlayer view.
    ///
    /// - Returns: A UIImage of the KYLPlayer view.
    open func takeSnapshot() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(self._KYLPlayerView.frame.size, false, UIScreen.main.scale)
        self._KYLPlayerView.drawHierarchy(in: self._KYLPlayerView.bounds, afterScreenUpdates: true)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }
    
    /// Return the av KYLPlayer layer for consumption by
    /// things such as Picture in Picture
    open func KYLPlayerLayer() -> AVPlayerLayer? {
        return self._KYLPlayerView.playerLayer
    }
}

// MARK: - loading funcs

extension KYLPlayer {
    
    fileprivate func setup(url: URL?) {
        guard isViewLoaded else { return }
        
        // ensure everything is reset beforehand
        if self.playbackState == .playing {
            self.pause()
        }
        
        //Reset autoplay flag since a new url is set.
        _hasAutoplayActivated = false
        if autoplay {
            playbackState = .playing
        } else {
            playbackState = .stopped
        }
        
        //        self.setupKYLPlayerItem(nil)
        
        if let url = url {
            let asset = AVURLAsset(url: url, options: .none)
            self.setupAsset(asset)
        }
    }
    
    fileprivate func setupAsset(_ asset: AVAsset) {
        guard isViewLoaded else { return }
        
        if self.playbackState == .playing {
            self.pause()
        }
        
        self.bufferingState = .unknown
        
        self._asset = asset
        
        let keys = [KYLPlayerTracksKey, KYLPlayerPlayableKey, KYLPlayerDurationKey]
        self._asset?.loadValuesAsynchronously(forKeys: keys, completionHandler: { () -> Void in
            for key in keys {
                var error: NSError? = nil
                let status = self._asset?.statusOfValue(forKey: key, error:&error)
                if status == .failed {
                    self.playbackState = .failed
                    return
                }
            }
            
            if let asset = self._asset {
                if !asset.isPlayable {
                    self.playbackState = .failed
                    return
                }
                
                let KYLPlayerItem = AVPlayerItem(asset:asset)
                self.setupKYLPlayerItem(KYLPlayerItem)
            }
        })
    }
    
    
    fileprivate func setupKYLPlayerItem(_ KYLPlayerItem: AVPlayerItem?) {
        self._KYLPlayerItem?.removeObserver(self, forKeyPath: KYLPlayerFullBufferKey, context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.removeObserver(self, forKeyPath: KYLPlayerEmptyBufferKey, context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.removeObserver(self, forKeyPath: KYLPlayerKeepUpKey, context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.removeObserver(self, forKeyPath: KYLPlayerStatusKey, context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.removeObserver(self, forKeyPath: KYLPlayerLoadedTimeRangesKey, context: &KYLPlayerItemObserverContext)
        
        if let currentKYLPlayerItem = self._KYLPlayerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentKYLPlayerItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: currentKYLPlayerItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: currentKYLPlayerItem)
            
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemTimeJumped, object: currentKYLPlayerItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemNewAccessLogEntry, object: currentKYLPlayerItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemNewErrorLogEntry, object: currentKYLPlayerItem)
        }
        
        self._KYLPlayerItem = KYLPlayerItem
        
        if let seek = _seekTimeRequested, self._KYLPlayerItem != nil {
            _seekTimeRequested = nil
            self.seek(to: seek)
        }
        
        self._KYLPlayerItem?.addObserver(self, forKeyPath: KYLPlayerEmptyBufferKey, options: [.new, .old], context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.addObserver(self, forKeyPath: KYLPlayerFullBufferKey, options: [.new, .old], context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.addObserver(self, forKeyPath: KYLPlayerKeepUpKey, options: [.new, .old], context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.addObserver(self, forKeyPath: KYLPlayerStatusKey, options: [.new, .old], context: &KYLPlayerItemObserverContext)
        self._KYLPlayerItem?.addObserver(self, forKeyPath: KYLPlayerLoadedTimeRangesKey, options: [.new, .old], context: &KYLPlayerItemObserverContext)
        
        if let updatedKYLPlayerItem = self._KYLPlayerItem {
            NotificationCenter.default.addObserver(self, selector: #selector(KYLPlayerItemDidPlayToEndTime(_:)), name: .AVPlayerItemDidPlayToEndTime, object: updatedKYLPlayerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(KYLPlayerItemFailedToPlayToEndTime(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: updatedKYLPlayerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(KYLPlayerItemPlaybackStalled(_:)), name: .AVPlayerItemPlaybackStalled, object: updatedKYLPlayerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(KYLPlayerItemTimeJumped(_:)), name: .AVPlayerItemTimeJumped, object: updatedKYLPlayerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(KYLPlayerItemNewAccessLogEntry(_:)), name: .AVPlayerItemNewAccessLogEntry, object: updatedKYLPlayerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(KYLPlayerItemNewErrorLogEntry(_:)), name: .AVPlayerItemNewErrorLogEntry, object: updatedKYLPlayerItem)
        }
        
        self._avKYLPlayer.replaceCurrentItem(with: self._KYLPlayerItem)
        
        // update new KYLPlayerItem settings
        if self.playbackLoops {
            self._avKYLPlayer.actionAtItemEnd = .none
        } else {
            self._avKYLPlayer.actionAtItemEnd = .pause
        }
    }
    
}

// MARK: - NSNotifications

extension KYLPlayer {
    
    // MARK: - AVKYLPlayerItem
    
    @objc internal func KYLPlayerItemDidPlayToEndTime(_ aNotification: Notification) {
        if self.playbackLoops {
            self.playbackDelegate?.KYLPlayerPlaybackWillLoop(self)
            self._avKYLPlayer.seek(to: CMTime.zero)
        } else {
            if self.playbackFreezesAtEnd {
                self.stop()
            } else {
                self._avKYLPlayer.seek(to: CMTime.zero, completionHandler: { _ in
                    self.stop()
                })
            }
        }
    }
    
    @objc internal func KYLPlayerItemFailedToPlayToEndTime(_ aNotification: Notification) {
        print("\(#function), \(bufferingState), \(bufferSize), \(playbackState)")
        self.playbackState = .failed
    }
    
    @objc internal func KYLPlayerItemPlaybackStalled(_ notifi:Notification){
        print("\(#function), \(bufferingState), \(bufferSize), \(playbackState)")
    }
    
    @objc internal func KYLPlayerItemTimeJumped(_ notifi:Notification){
        print("\(#function), \(bufferingState), \(bufferSize), \(playbackState)")
        
    }
    
    @objc internal func KYLPlayerItemNewAccessLogEntry(_ notifi:Notification){
        print("\(#function), \(bufferingState), \(bufferSize), \(playbackState)")
    }
    
    @objc internal func KYLPlayerItemNewErrorLogEntry(_ notifi:Notification){
        print("\(#function), \(bufferingState), \(bufferSize), \(playbackState)")
        self.playbackState = .failed
    }
    
    
    // MARK: - UIApplication
    
    internal func addApplicationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillResignActive(_:)), name: .UIApplication.willResignActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidBecomeActive(_:)), name: .UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidEnterBackground(_:)), name: .UIApplication.didEnterBackgroundNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillEnterForeground(_:)), name: .UIApplication.willEnterForegroundNotification, object: UIApplication.shared)
    }
    
    internal func removeApplicationObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - handlers
    
    @objc internal func handleApplicationWillResignActive(_ aNotification: Notification) {
        if self.playbackState == .playing && self.playbackPausesWhenResigningActive {
            self.pause()
        }
    }
    
    @objc internal func handleApplicationDidBecomeActive(_ aNotification: Notification) {
        if self.playbackState != .playing && self.playbackResumesWhenBecameActive {
            self.play()
        }
    }
    
    @objc internal func handleApplicationDidEnterBackground(_ aNotification: Notification) {
        if self.playbackState == .playing && self.playbackPausesWhenBackgrounded {
            self.pause()
        }
    }
    
    @objc internal func handleApplicationWillEnterForeground(_ aNoticiation: Notification) {
        if self.playbackState != .playing && self.playbackResumesWhenEnteringForeground {
            self.play()
        }
    }
    
}

// MARK: - KVO

// KVO contexts

private var KYLPlayerObserverContext = 0
private var KYLPlayerItemObserverContext = 0
private var KYLPlayerLayerObserverContext = 0

// KVO KYLPlayer keys

private let KYLPlayerTracksKey = "tracks"
private let KYLPlayerPlayableKey = "playable"
private let KYLPlayerDurationKey = "duration"
private let KYLPlayerRateKey = "rate"

// KVO KYLPlayer item keys

private let KYLPlayerStatusKey = "status"
private let KYLPlayerEmptyBufferKey = "playbackBufferEmpty"
private let KYLPlayerFullBufferKey = "playbackBufferFull"
private let KYLPlayerKeepUpKey = "playbackLikelyToKeepUp"
private let KYLPlayerLoadedTimeRangesKey = "loadedTimeRanges"


// KVO KYLPlayer layer keys

private let KYLPlayerReadyForDisplayKey = "readyForDisplay"

extension KYLPlayer {
    
    // MARK: - AVKYLPlayerLayerObservers
    
    internal func addKYLPlayerLayerObservers() {
        self._KYLPlayerView.layer.addObserver(self, forKeyPath: KYLPlayerReadyForDisplayKey, options: [.new, .old], context: &KYLPlayerLayerObserverContext)
    }
    
    internal func removeKYLPlayerLayerObservers() {
        self._KYLPlayerView.layer.removeObserver(self, forKeyPath: KYLPlayerReadyForDisplayKey, context: &KYLPlayerLayerObserverContext)
    }
    
    // MARK: - AVKYLPlayerObservers
    
    internal func addKYLPlayerObservers() {
        self._timeObserver = self._avKYLPlayer.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 100), queue: DispatchQueue.main, using: { [weak self] timeInterval in
            guard let strongSelf = self
                else {
                    return
            }
            strongSelf.playbackDelegate?.KYLPlayerCurrentTimeDidChange(strongSelf)
        })
        self._avKYLPlayer.addObserver(self, forKeyPath: KYLPlayerRateKey, options: [.new, .old], context: &KYLPlayerObserverContext)
    }
    
    internal func removeKYLPlayerObservers() {
        if let observer = self._timeObserver {
            self._avKYLPlayer.removeTimeObserver(observer)
        }
        self._avKYLPlayer.removeObserver(self, forKeyPath: KYLPlayerRateKey, context: &KYLPlayerObserverContext)
    }
    
    // MARK: -
    
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        
        // KYLPlayerRateKey, KYLPlayerObserverContext
        //print("\(#function), keyPath=\(String(describing: keyPath)), obj = \(String(describing: object)), change =\(String(describing: change))")
        if context == &KYLPlayerItemObserverContext {
            
            // KYLPlayerStatusKey
            
            if keyPath == KYLPlayerKeepUpKey {
                
                // KYLPlayerKeepUpKey
                
                if let item = self._KYLPlayerItem {
                    
                    if item.isPlaybackLikelyToKeepUp {
                        self.bufferingState = .ready
                        if self.playbackState == .playing {
                            self.playFromCurrentTime()
                        }
                    }
                }
                
                if let status = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                    switch status.intValue {
                    case AVPlayer.Status.readyToPlay.rawValue:
                        self._KYLPlayerView.playerLayer.player = self._avKYLPlayer
                        self._KYLPlayerView.playerLayer.isHidden = false
                    case AVPlayer.Status.failed.rawValue:
                        self.playbackState = PlaybackState.failed
                    default:
                        break
                    }
                }
                
            } else if keyPath == KYLPlayerEmptyBufferKey {
                
                // KYLPlayerEmptyBufferKey
                
                if let item = self._KYLPlayerItem {
                    print("isPlaybackBufferEmpty = \(item.isPlaybackBufferEmpty)")
                    if item.isPlaybackBufferEmpty {
                        self.bufferingState = .delayed
                    }
                    else {
                        self.bufferingState = .ready
                    }
                }
                
                if let status = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                    switch status.intValue {
                    case AVPlayer.Status.readyToPlay.rawValue:
                        self._KYLPlayerView.playerLayer.player = self._avKYLPlayer
                        self._KYLPlayerView.playerLayer.isHidden = false
                    case AVPlayer.Status.failed.rawValue:
                        self.playbackState = PlaybackState.failed
                    default:
                        break
                    }
                }
                
            } else if keyPath == KYLPlayerLoadedTimeRangesKey {
                
                // KYLPlayerLoadedTimeRangesKey
                
                if let item = self._KYLPlayerItem {
                    self.bufferingState = .ready
                    
                    let timeRanges = item.loadedTimeRanges
                    if let timeRange = timeRanges.first?.timeRangeValue {
                        let bufferedTime = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
                        if _lastBufferTime != bufferedTime {
                            self.executeClosureOnMainQueueIfNecessary {
                                self.KYLPlayerDelegate?.KYLPlayerBufferTimeDidChange(bufferedTime)
                            }
                            _lastBufferTime = bufferedTime
                        }
                    }
                    
                    let currentTime = CMTimeGetSeconds(item.currentTime())
                    if ((_lastBufferTime - currentTime) >= self.bufferSize ||
                        _lastBufferTime == maximumDuration ||
                        timeRanges.first == nil)
                        && self.playbackState == .playing
                    {
                        self.play()
                    }
                    
                }
                
            }
            
        } else if context == &KYLPlayerLayerObserverContext {
            if self._KYLPlayerView.playerLayer.isReadyForDisplay {
                self.executeClosureOnMainQueueIfNecessary {
                    self.KYLPlayerDelegate?.KYLPlayerReady(self)
                }
            }
        }
        else if keyPath == KYLPlayerFullBufferKey {
            
            // KYLPlayerFullBufferKey
            
            if let item = self._KYLPlayerItem {
                print("isPlaybackBufferFull = \(item.isPlaybackBufferFull)")
            }
            
            
        }
        
    }
    
}

// MARK: - queues

extension KYLPlayer {
    
    internal func executeClosureOnMainQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async(execute: closure)
        }
    }
    
}

// MARK: - KYLPlayerView

internal class KYLPlayerView: UIView {
    
    // MARK: - properties
    
    override class var layerClass: AnyClass {
        get {
            return AVPlayerLayer.self
        }
    }
    
    var playerLayer: AVPlayerLayer {
        get {
            return self.layer as! AVPlayerLayer
        }
    }
    
    var player: AVPlayer? {
        get {
            return self.playerLayer.player
        }
        set {
            self.playerLayer.player = newValue
        }
    }
    
    var fillMode: String {
        get {
            return self.playerLayer.videoGravity.rawValue
        }
        set {
            self.playerLayer.videoGravity = AVLayerVideoGravity(rawValue: newValue)
        }
    }
    
    // MARK: - object lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.playerLayer.backgroundColor = UIColor.black.cgColor
        self.playerLayer.fillMode = CAMediaTimingFillMode(rawValue: KYLPlayerFillMode.resizeAspectFit.avFoundationType)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.playerLayer.backgroundColor = UIColor.black.cgColor
        self.playerLayer.fillMode = CAMediaTimingFillMode(rawValue: KYLPlayerFillMode.resizeAspectFit.avFoundationType)
    }
    
    deinit {
        self.player?.pause()
        self.player = nil
    }
    
}
