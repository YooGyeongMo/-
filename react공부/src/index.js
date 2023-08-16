import ReactDOM from 'react-dom/client'; //pakcage.json 에 있는 파일을 이용해서 reactDom을 import 하기 때문에 js에서 사용가능

import './index.css';
import App from './App'; // ./는 현재 index.js가 있는 파일 경로에서App.js를 찾는다는 의미이다. .js는 생략가능 그러나 .css는 불가능

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />); // public 폴더의 index.html의 div태그안에서 있는 것들이 랜더링된 컴포넌트들을 불러온다는 뜻이다.
//왜냐하면 src 폴더의 index.js파일이 최초로 먼저 실행되기 때문이다.
