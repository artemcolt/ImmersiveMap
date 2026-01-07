//
//  ImmersiveMapView.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import UIKit
import Metal

public class ImmersiveMapUIView: UIView, UIGestureRecognizerDelegate {
    public override class var layerClass: AnyClass { return CAMetalLayer.self }
    
    private let config: MapConfiguration
    
    override init(frame: CGRect) {
        self.config = .default
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        self.config = .default
        super.init(coder: coder)
        setup()
    }
    
    init(frame: CGRect, config: MapConfiguration) {
        self.config = config
        super.init(frame: frame)
        setup()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds  // Убедимся, что layer следует за bounds UIView
        
        let scale = metalLayer.contentsScale
        let width = bounds.width * scale
        let height = bounds.height * scale
        let newDrawableSize = CGSize(width: width, height: height)
        
        if metalLayer.drawableSize != newDrawableSize {
            metalLayer.drawableSize = newDrawableSize  // Вручную обновляем drawableSize при каждом layout
            redraw = true
        }
        
        pitchSlider.frame = CGRect(x: 30, y: bounds.height - 130, width: 20, height: 100)
    }
    
    private var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    private var pitchSlider: UISlider!
    private var renderer: Renderer?
    private var displayLink: CADisplayLink?
    var redraw: Bool = false
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: self, selector: #selector(renderLoop))
        displayLink?.add(to: .main, forMode: .default)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    private func setup() {
        metalLayer.contentsScale = UIScreen.main.scale
        renderer = Renderer(layer: metalLayer, uiView: self, config: config)
        
        // Добавляем обработчик жеста панорамирования одним пальцем
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
        
        // Добавляем обработчик жеста поворота двумя пальцами
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture.delegate = self
        addGestureRecognizer(rotationGesture)
        
        // Добавляем обработчик жеста зума двумя пальцами
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        addGestureRecognizer(pinchGesture)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        
        // Добавляем ползунок для контроля pitch (наклона камеры)
        pitchSlider = UISlider()
        pitchSlider.minimumValue = 0.0
        pitchSlider.maximumValue = config.maxPitch
        pitchSlider.value = config.maxPitch
        pitchSlider.addTarget(self, action: #selector(handlePitchChange(_:)), for: .valueChanged)
        pitchSlider.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)  // Делаем вертикальным
        addSubview(pitchSlider)
        
        startDisplayLink()
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Позволяем одновременное распознавание поворота и зума
        if (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) ||
           (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) {
            return true
        }
        return false
    }
    
    @objc private func handleDoubleTap(_ gestrue: UITapGestureRecognizer) {
        _ = gestrue.location(in: self)
        renderer?.switchRenderMode()
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let renderer = renderer else { return }
        let rotation = gesture.rotation
        let sensitivity = Float(-0.6)  // Можно настроить чувствительность поворота
        // Применяем поворот yaw к рендереру (предполагается, что в Renderer есть метод rotateYaw(delta:))
        renderer.cameraControl.rotateYaw(delta: Float(rotation) * sensitivity)
        // Сбрасываем rotation для накопления изменений
        gesture.rotation = 0
        // Перерисовываем вид после поворота
        redraw = true
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let renderer = renderer else { return }
        
        let translation = gesture.translation(in: self)
        let sensetivity = 0.1
        
        // Применяем панорамирование к рендереру (предполагается, что в Renderer есть метод pan(deltaX:deltaY:))
        renderer.cameraControl.pan(deltaX: Double(translation.x) * sensetivity, deltaY: Double(translation.y) * sensetivity)
        
        // Сбрасываем translation для накопления изменений
        gesture.setTranslation(.zero, in: self)
        
        // Перерисовываем вид после панорамирования
        redraw = true
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let renderer = renderer else { return }
        
        let scale = gesture.scale
        // Применяем зум к рендереру (предполагается, что в Renderer есть метод zoom(scale:))
        renderer.cameraControl.zoom(scale: scale)
        // Сбрасываем scale для накопления изменений
        gesture.scale = 1.0
        // Перерисовываем вид после зума
        redraw = true
    }
    
    @objc private func handlePitchChange(_ slider: UISlider) {
        guard let renderer = renderer else { return }
        
        renderer.cameraControl.rotatePitch(pitch: slider.value)
        
        // Перерисовываем вид после изменения pitch
        redraw = true
    }
    
    @objc private func renderLoop() {
        if redraw || config.continueRendering {
            render()
            redraw = false
        }
    }
    
    private func render() {
        if bounds.width > 0 && bounds.height > 0 {
            renderer?.render(to: metalLayer)
        }
    }
    
    deinit {
        displayLink?.invalidate()
    }
}
