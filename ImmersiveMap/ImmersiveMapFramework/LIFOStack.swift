//
//  LIFOStack.swift
//  TucikMap
//
//  Created by Artem on 8/20/25.
//

class LIFOStack<T> {
    private var elements: [T?]
    private var head: Int = 0
    private var tail: Int = 0
    private var capacity: Int
    private var size: Int = 0
    
    // Инициализация с заданной емкостью
    init(capacity: Int) {
        self.capacity = max(1, capacity) // Минимальная емкость 1
        self.elements = [T?](repeating: nil, count: capacity)
    }
    
    // Добавление элемента на вершину стека
    @discardableResult
    func push(_ element: T) -> Bool {
        elements[tail] = element
        tail = (tail + 1) % capacity
        if size < capacity {
            size += 1
        } else {
            // Если стек полон, сдвигаем head, перезаписывая старый элемент (bottom)
            head = (head + 1) % capacity
        }
        return true
    }
    
    // Удаление и возврат верхнего элемента
    func pop() -> T? {
        guard size > 0 else { return nil } // Проверка на пустой стек
        let topIndex = (tail - 1 + capacity) % capacity
        let element = elements[topIndex]
        elements[topIndex] = nil
        tail = (tail - 1 + capacity) % capacity
        size -= 1
        return element
    }
    
    // Получение верхнего элемента без удаления
    var top: T? {
        return size > 0 ? elements[(tail - 1 + capacity) % capacity] : nil
    }
    
    // Проверка, пуст ли стек
    var isEmpty: Bool {
        return size == 0
    }
    
    // Проверка, заполнен ли стек
    var isFull: Bool {
        return size == capacity
    }
    
    // Текущее количество элементов
    var count: Int {
        return size
    }
    
    // Очистка стека
    func clear() {
        elements = [T?](repeating: nil, count: capacity)
        head = 0
        tail = 0
        size = 0
    }
}
