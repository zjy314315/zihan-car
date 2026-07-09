import { TCPClientManager } from '../tcp/TCPClientManager'
import { TCPClientSendUtils } from '../tcp/TCPClientSendUtils'
import { CarEncode } from './CarEncode';
import { CarDirection } from './CarEnum';

class CarApi {
  /**
   *
   * @param d
   */
  carBtnCtrl(d: CarDirection): void {
    this.send(CarEncode.ButtonCarEncode(d))
  }

  send(message: string): void {
    TCPClientManager.getInstance().sendMessage(message)
  }
}


let carApi = (new CarApi())

export { carApi, }