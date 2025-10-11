//
//  ImmersiveMapView.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import UIKit
import Metal

public class ImmersiveMapUIView: UIView {
    public override class var layerClass: AnyClass { return CAMetalLayer.self }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
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
            redraw()
        }
        
        pitchSlider.frame = CGRect(x: 30, y: bounds.height - 130, width: 20, height: 100)
    }
    
    private var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    private var pitchSlider: UISlider!
    private var renderer: Renderer?
    private var displayLink: CADisplayLink?
    
    var isAnimating: Bool = false {
        didSet {
            if isAnimating {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }
    }
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }  // Уже запущен
        
        displayLink = CADisplayLink(target: self, selector: #selector(renderLoop))
        displayLink?.add(to: .main, forMode: .default)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    
    public func redraw() {
        if bounds.width > 0 && bounds.height > 0 {  // Проверяем, чтобы избежать рендеринга в нулевом размере
            renderer?.render(to: metalLayer)
        }
    }
    
    private func setup() {
        metalLayer.contentsScale = UIScreen.main.scale
        renderer = Renderer(layer: metalLayer)
        
        // Добавляем обработчик жеста панорамирования одним пальцем
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
        
        // Добавляем обработчик жеста поворота двумя пальцами
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        addGestureRecognizer(rotationGesture)
        
        // Добавляем обработчик жеста зума двумя пальцами
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)
        
        // Добавляем ползунок для контроля pitch (наклона камеры)
        pitchSlider = UISlider()
        pitchSlider.minimumValue = 0.0
        pitchSlider.maximumValue = MapParameters.maxPitch
        pitchSlider.value = MapParameters.maxPitch
        pitchSlider.addTarget(self, action: #selector(handlePitchChange(_:)), for: .valueChanged)
        pitchSlider.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)  // Делаем вертикальным
        addSubview(pitchSlider)
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
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let renderer = renderer else { return }
        let rotation = gesture.rotation
        let sensitivity = Float(-0.6)  // Можно настроить чувствительность поворота
        // Применяем поворот yaw к рендереру (предполагается, что в Renderer есть метод rotateYaw(delta:))
        renderer.cameraControl.rotateYaw(delta: Float(rotation) * sensitivity)
        // Сбрасываем rotation для накопления изменений
        gesture.rotation = 0
        // Перерисовываем вид после поворота
        redraw()
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
        redraw()
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let renderer = renderer else { return }
        
        let scale = gesture.scale
        // Применяем зум к рендереру (предполагается, что в Renderer есть метод zoom(scale:))
        renderer.cameraControl.zoom(scale: Float(scale))
        // Сбрасываем scale для накопления изменений
        gesture.scale = 1.0
        // Перерисовываем вид после зума
        redraw()
    }
    
    @objc private func handlePitchChange(_ slider: UISlider) {
        guard let renderer = renderer else { return }
        
        renderer.cameraControl.rotatePitch(pitch: slider.value)
        
        // Перерисовываем вид после изменения pitch
        redraw()
    }
    
    @objc private func renderLoop() {
        renderer?.render(to: metalLayer)
    }
    
    deinit {
        displayLink?.invalidate()
    }
}
