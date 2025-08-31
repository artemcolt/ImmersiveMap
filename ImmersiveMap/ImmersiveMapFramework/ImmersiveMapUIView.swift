//
//  ImmersiveMapView.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import UIKit
import Metal

public class ImmersiveMapUIView: UIView {
    private var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    private var renderer: Renderer?
    private var displayLink: CADisplayLink?
    
    private var isAnimating: Bool = false {
        didSet {
            if isAnimating {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }
    }
    
    public func startAnimation() {
        isAnimating = true
    }
    
    public func stopAnimation() {
        isAnimating = false
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
    
    public override class var layerClass: AnyClass { return CAMetalLayer.self }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    public func redraw() {
        if bounds.width > 0 && bounds.height > 0 {  // Проверяем, чтобы избежать рендеринга в нулевом размере
            renderer?.render(to: metalLayer)
        }
    }
    
    private func setup() {
        metalLayer.contentsScale = UIScreen.main.scale
        renderer = Renderer(layer: metalLayer)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds  // Убедимся, что layer следует за bounds UIView
        let scale = metalLayer.contentsScale
        let newDrawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metalLayer.drawableSize = newDrawableSize  // Вручную обновляем drawableSize при каждом layout
        //print("layoutSubviews called: bounds = \(bounds), drawableSize = \(newDrawableSize)")  // Для отладки
        
        redraw()
    }
    
    @objc private func renderLoop() {
        renderer?.render(to: metalLayer)
    }
    
    deinit {
        displayLink?.invalidate()
    }
}
